#!/usr/bin/env bash
# LifeLine: patch help for vendored code. Fetches the recorded upstream version and a
# newer one, and writes two diffs so an update or CVE fix can be carried over by hand:
#   upstream.diff  recorded version -> target version   (what changed upstream)
#   local.diff     recorded version -> our vendored copy (what we changed locally)
# Usage: upstream-diff.sh <project-root> <ledger-entry-name> [target-version]
#   target defaults to the registry's latest (npm/PyPI) or the latest GitHub tag.
# Output lines:
#   WORKDIR|<dir>                           downloads + diffs live here (temp dir, never the project);
#                                           left in place for reading - the caller deletes it
#   FETCHED|recorded|target ,version, path
#   UPSTREAM|<n-files-changed>|<dir>/upstream.diff
#   LOCAL|<n-files-changed>|<dir>/local.diff
#   UNMAPPED|<vendored-file>               no counterpart found upstream (set Upstream-Path)
#   ERROR|<reason>
# Sources: npm registry tarballs, PyPI sdists, GitHub tag archives. Downloaded archives
# are only extracted and diffed - nothing in them is ever executed.
set -u

ROOT="${1:-}"
NAME="${2:-}"
TARGET="${3:-}"
[ -n "$ROOT" ] && [ -n "$NAME" ] || { echo "usage: upstream-diff.sh <project-root> <entry> [target-version]" >&2; exit 2; }
LEDGER="$ROOT/VENDORED.md"
[ -f "$LEDGER" ] || { echo "ERROR|no VENDORED.md in $ROOT"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "ERROR|curl missing"; exit 0; }

field() {
  awk -v want="$NAME" -v key="$1" '
    /^## / { cur = substr($0, 4) }
    cur == want && index($0, "- " key ":") == 1 {
      v = substr($0, length(key) + 4); sub(/^[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); print v; exit
    }' "$LEDGER"
}
ECO=$(field Ecosystem); PKG=$(field Package-Name); VER=$(field Version)
SRC=$(field Source); LOC=$(field Location); UPATH=$(field Upstream-Path)
[ -n "$VER" ] && [ -n "$LOC" ] || { echo "ERROR|entry '$NAME' not found or has no Version/Location"; exit 0; }

eco_lc=$(printf '%s' "$ECO" | tr 'A-Z' 'a-z')
ownerrepo=""
case "$SRC" in *github.com/*) ownerrepo=$(printf '%s' "$SRC" | sed -E 's|.*github\.com/([^/ ]+/[^/ ]+).*|\1|; s|\.git$||') ;; esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/lifeline-diff.XXXXXX") || exit 1
echo "WORKDIR|$WORK"

# Default target: registry latest, else newest GitHub tag.
if [ -z "$TARGET" ]; then
  case "$eco_lc" in
    npm)  TARGET=$(curl -s --max-time 15 "https://registry.npmjs.org/$(printf '%s' "$PKG" | sed 's|/|%2F|')/latest" |
            sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -1) ;;
    pypi) TARGET=$(curl -s --max-time 15 "https://pypi.org/pypi/$PKG/json" |
            sed -n 's/.*"info":{.*"version":"\([^"]*\)".*/\1/p' | head -1) ;;
  esac
  if [ -z "$TARGET" ] && [ -n "$ownerrepo" ]; then
    TARGET=$(curl -sL --max-time 15 "https://api.github.com/repos/$ownerrepo/tags?per_page=1" |
      sed -n 's/.*"name"[^"]*"\([^"]*\)".*/\1/p' | head -1)
  fi
fi
[ -n "$TARGET" ] || { echo "ERROR|could not determine a target version - pass one explicitly"; exit 0; }

# Fetch one version into $WORK/<slot>/ (archive top folder stripped).
fetch() {
  slot="$1"; v="$2"; url=""
  case "$eco_lc" in
    npm)  url=$(curl -s --max-time 15 "https://registry.npmjs.org/$(printf '%s' "$PKG" | sed 's|/|%2F|')/$v" |
            sed -n 's/.*"tarball":"\([^"]*\)".*/\1/p' | head -1) ;;
    pypi) url=$(curl -s --max-time 15 "https://pypi.org/pypi/$PKG/$v/json" | tr ',' '\n' |
            sed -n 's/.*"url": *"\([^"]*\.tar\.gz\)".*/\1/p' | head -1) ;;
  esac
  if [ -z "$url" ] && [ -n "$ownerrepo" ]; then
    for ref in "$v" "v${v#v}"; do
      if curl -sfL --max-time 30 -o "$WORK/$slot.tgz" "https://codeload.github.com/$ownerrepo/tar.gz/refs/tags/$ref"; then
        url=local; break
      fi
    done
  fi
  [ -n "$url" ] || return 1
  [ "$url" = local ] || curl -sfL --max-time 60 -o "$WORK/$slot.tgz" "$url" || return 1
  mkdir -p "$WORK/$slot"
  tar -xzf "$WORK/$slot.tgz" -C "$WORK/$slot" --strip-components 1 2>/dev/null || return 1
  echo "FETCHED|$slot|$v|$WORK/$slot"
}
fetch recorded "$VER" || { echo "ERROR|could not fetch recorded version $VER"; exit 0; }
fetch target "$TARGET" || { echo "ERROR|could not fetch target version $TARGET"; exit 0; }

# Which upstream path does a vendored file correspond to? Upstream-Path wins, then the
# same relative path, then a unique basename match.
counterpart() {
  rel="$1"
  if [ -n "$UPATH" ]; then
    if [ -f "$ROOT/$LOC" ]; then echo "$UPATH"; else echo "${UPATH%/}/$rel"; fi
    return
  fi
  [ -f "$WORK/recorded/$rel" ] && { echo "$rel"; return; }
  m=$(cd "$WORK/recorded" && find . -type f -name "$(basename "$rel")" | sed 's|^\./||')
  [ "$(printf '%s\n' "$m" | grep -c .)" -eq 1 ] && echo "$m"
}

if [ -f "$ROOT/$LOC" ]; then
  (cd "$ROOT" && basename "$LOC") > "$WORK/vfiles"; VBASE=$(dirname "$ROOT/$LOC")
else
  (cd "$ROOT/$LOC" && find . -type f ! -name .DS_Store | sed 's|^\./||' | LC_ALL=C sort) > "$WORK/vfiles"; VBASE="$ROOT/$LOC"
fi

: > "$WORK/upstream.diff"; : > "$WORK/local.diff"; up=0; lo=0
while IFS= read -r rel; do
  cp=$(counterpart "$rel")
  if [ -f "$ROOT/$LOC" ]; then shown="$LOC"; else shown="${LOC%/}/$rel"; fi
  if [ -z "$cp" ] || [ ! -f "$WORK/recorded/$cp" ]; then echo "UNMAPPED|$shown"; continue; fi
  if [ -f "$WORK/target/$cp" ]; then
    diff -u --label "a/$cp ($VER)" --label "b/$cp ($TARGET)" "$WORK/recorded/$cp" "$WORK/target/$cp" >> "$WORK/upstream.diff" || up=$((up + 1))
  else
    printf -- '--- a/%s (%s)\n+++ /dev/null (removed in %s)\n' "$cp" "$VER" "$TARGET" >> "$WORK/upstream.diff"; up=$((up + 1))
  fi
  diff -u --label "upstream/$cp ($VER)" --label "vendored/$rel" "$WORK/recorded/$cp" "$VBASE/$rel" >> "$WORK/local.diff" || lo=$((lo + 1))
done < "$WORK/vfiles"

echo "UPSTREAM|$up|$WORK/upstream.diff"
echo "LOCAL|$lo|$WORK/local.diff"
