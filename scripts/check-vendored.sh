#!/usr/bin/env bash
# LifeLine: check every VENDORED.md ledger entry for upstream updates and known CVEs.
# Usage: check-vendored.sh [project-root]
#        check-vendored.sh --hash <project-root> <location>   checksum for a new entry
# Output lines:
#        check-vendored.sh --compare <recorded> <latest>      version verdict only (tests)
# Output lines:
#   NOLEDGER|<path>                                    no ledger file - nothing to check
#   OFFLINE|<reason>                                   remote checks skipped, say so in the report
#   ENTRY|name|recorded|latest-upstream|osv-hits|status|local|version
#   UPSTREAM|name|upstream-path|identical|differs|missing|unchecked
#       GitHub-sourced file entries with an Upstream-Path only: is the file at that path
#       on the default branch byte-identical to the recorded Checksum? "missing" = the
#       recorded path does not exist upstream (the ledger points at the wrong file).
#   HASH|<location>|sha256:<hex>                       (--hash mode)
# status: current | update-available | cve-warning | unchecked
#   current   = every check that applies to the entry ran and found nothing
#   unchecked = offline, or a check that applies could not run (no registry identity
#               and no GitHub Source, OSV request failed) - never reported as current
# version: current | update-available | ahead | unchecked  - upstream version only, never CVEs.
#   Compared by number, not by string: "v7.222" against a recorded "9.000" is "ahead"
#   (the copy is newer than the newest release or tag, e.g. taken from the default
#   branch), not an update. A pre-release recorded against its final release
#   ("1.0.0-rc1" vs "1.0.0") is an update.
#   This is the only status written to VENDORED.md: the ledger is committed, so it must
#   not hint at open vulnerabilities. `status` (with cve-warning) goes to the private
#   report only.
# local: unchanged | modified | missing | untracked | unknown   (works offline)
#   compares the files at `Location` with the recorded `Checksum`; "modified" means
#   someone edited vendored code after it was recorded - intended or not, it must be
#   explained in the ledger (`Modifications`) and the Checksum re-recorded.
# Latest upstream: the registry's default version (api.deps.dev) for registry entries,
# GitHub releases/tags for the rest.
# The script only reads; updating Last-Checked/Status in VENDORED.md is the skill's job.
set -u

# sha256 of stdin with whatever the system has.
sha_stdin() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 | sed 's/.*= *//'
  else return 1
  fi
}

# Checksum of a vendored location: a file's content, or for a directory the hash of
# "<file-hash>  <relative-path>" lines in byte order - renames and additions count.
location_hash() {
  if [ -f "$1" ]; then
    sha_stdin < "$1"
  elif [ -d "$1" ]; then
    ( cd "$1" && find . -type f ! -name .DS_Store | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s  %s\n' "$(sha_stdin < "$f")" "${f#./}"
      done ) | sha_stdin
  else
    return 1
  fi
}

# Upstream version verdict for a recorded version: current | update-available | ahead.
# Numbers are compared piece by piece; a leading "v" and the build suffix are ignored.
version_verdict() {
  awk -v r="${1#v}" -v l="${2#v}" 'BEGIN {
    if (r == l) { print "current"; exit }
    cr = r; sub(/[-+].*/, "", cr); cl = l; sub(/[-+].*/, "", cl)
    nr = split(cr, x, /[^0-9]+/); nl = split(cl, y, /[^0-9]+/); n = nr > nl ? nr : nl
    for (i = 1; i <= n; i++) {
      if (x[i] + 0 < y[i] + 0) { print "update-available"; exit }
      if (x[i] + 0 > y[i] + 0) { print "ahead"; exit }
    }
    # Same numbers, different text: a pre-release against its release, or a renamed tag.
    print (r ~ /-/ && l !~ /-/) ? "update-available" : (r !~ /-/ && l ~ /-/) ? "ahead" : "current"
  }'
}

if [ "${1:-}" = "--compare" ]; then
  [ $# -eq 3 ] || { echo "usage: check-vendored.sh --compare <recorded> <latest>" >&2; exit 2; }
  version_verdict "$2" "$3"; exit 0
fi

if [ "${1:-}" = "--hash" ]; then
  [ $# -eq 3 ] || { echo "usage: check-vendored.sh --hash <project-root> <location>" >&2; exit 2; }
  h=$(cd "$2" 2>/dev/null && location_hash "$3") || { echo "ERROR|cannot hash $3" >&2; exit 1; }
  echo "HASH|$3|sha256:$h"
  exit 0
fi

ROOT="${1:-.}"
LEDGER="$ROOT/VENDORED.md"
[ -f "$LEDGER" ] || { echo "NOLEDGER|$LEDGER"; exit 0; }

NET=1
if [ "${LIFELINE_OFFLINE:-0}" = 1 ]; then
  NET=0
elif command -v curl >/dev/null 2>&1; then
  curl -s --max-time 6 -o /dev/null "https://api.osv.dev" 2>/dev/null || NET=0
else
  NET=0
fi
[ "$NET" -eq 0 ] && echo "OFFLINE|network unavailable or curl missing - remote checks skipped"

# Escape a value for a JSON string literal (backslash and double quote).
json_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# OSV ecosystem name -> deps.dev system; empty when deps.dev does not cover it.
depsdev_system() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    npm) echo npm ;; pypi) echo pypi ;; crates.io) echo cargo ;; go) echo go ;;
    maven) echo maven ;; nuget) echo nuget ;;
  esac
}
urlenc() { printf '%s' "$1" | sed 's/%/%25/g; s/@/%40/g; s|/|%2F|g; s/:/%3A/g; s/ /%20/g'; }

awk '
  function flush() { if (name != "") print name "|" eco "|" pkg "|" ver "|" src "|" loc "|" sum "|" upath }
  /^## /   { flush(); name = substr($0, 4); eco = ""; pkg = ""; ver = ""; src = ""; loc = ""; sum = ""; upath = "" }
  /^- Upstream-Path:/ { sub(/^- Upstream-Path:[ \t]*/, ""); sub(/[ \t]+#.*$/, ""); upath = $0 }
  /^- Location:/     { sub(/^- Location:[ \t]*/, "");     sub(/[ \t]+#.*$/, ""); loc = $0 }
  /^- Checksum:/     { sub(/^- Checksum:[ \t]*/, "");     sub(/[ \t]+#.*$/, ""); sum = $0 }
  /^- Source:/       { sub(/^- Source:[ \t]*/, "");       sub(/[ \t]+#.*$/, ""); src = $0 }
  /^- Ecosystem:/    { sub(/^- Ecosystem:[ \t]*/, "");    sub(/[ \t]+#.*$/, ""); eco = $0 }
  /^- Package-Name:/ { sub(/^- Package-Name:[ \t]*/, ""); sub(/[ \t]+#.*$/, ""); pkg = $0 }
  /^- Version:/      { sub(/^- Version:[ \t]*/, "");      sub(/[ \t]+#.*$/, ""); ver = $0 }
  END { flush() }
' "$LEDGER" | while IFS='|' read -r name eco pkg ver src loc sum upath; do
  [ -z "$name" ] && continue

  # --- OSV vulnerability lookup (only for entries in an ecosystem OSV covers; for a
  # GitHub repo or a file with no registry identity the check does not apply) ---
  osv=0
  osv_ok=1
  case " npm PyPI Maven Go crates.io NuGet RubyGems Packagist Pub Hex " in
    *" $eco "*) osv_eco=1 ;; *) osv_eco=0 ;;
  esac
  if [ "$osv_eco" -eq 1 ] && [ -n "$pkg" ] && [ "$pkg" != "none" ]; then
    osv_ok=0
    if [ "$NET" -eq 1 ]; then
      body=$(printf '{"package":{"name":"%s","ecosystem":"%s"},"version":"%s"}' \
        "$(json_str "$pkg")" "$(json_str "$eco")" "$(json_str "$ver")")
      resp=$(curl -s --max-time 10 -X POST "https://api.osv.dev/v1/query" \
        -H 'Content-Type: application/json' -d "$body" 2>/dev/null) || resp=""
      # A valid answer is {} (no vulns) or {"vulns":[...]}; anything else (empty,
      # {"code":..,"message":..}) means the check did not happen.
      case "$resp" in
        '{}'|*'"vulns"'*)
          osv_ok=1
          # "modified" is required on every OSV record and appears once per record;
          # "summary" is optional and missing on many PyPI/Go advisories.
          osv=$(printf '%s' "$resp" | grep -o '"modified"' | wc -l | tr -d ' 	')
          ;;
      esac
    fi
  fi

  # --- Upstream version lookup: registry first (that is what was copied), then GitHub ---
  latest=""
  sys=$(depsdev_system "$eco")
  if [ "$NET" -eq 1 ] && [ -n "$sys" ] && [ -n "$pkg" ] && [ "$pkg" != "none" ]; then
    latest=$(curl -s --max-time 10 "https://api.deps.dev/v3/systems/$sys/packages/$(urlenc "$pkg")" 2>/dev/null |
      grep -oE '"version":"[^"]*"\}(,"publishedAt":"[^"]*")?,"isDefault":true' | head -1 |
      sed -E 's/^"version":"([^"]*)".*/\1/')
  fi
  [ -n "$latest" ] || case "$src" in
    *github.com/*)
      ownerrepo=$(printf '%s' "$src" | sed -E 's|.*github\.com/([^/ ]+/[^/ ]+).*|\1|; s|\.git$||')
      if [ "$NET" -eq 1 ] && [ -n "$ownerrepo" ]; then
        latest=$(curl -s --max-time 10 "https://api.github.com/repos/$ownerrepo/releases/latest" 2>/dev/null |
          sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p' | head -1)
        if [ -z "$latest" ]; then
          latest=$(curl -s --max-time 10 "https://api.github.com/repos/$ownerrepo/tags?per_page=1" 2>/dev/null |
            sed -n 's/.*"name"[^"]*"\([^"]*\)".*/\1/p' | head -1)
        fi
      fi
      ;;
  esac

  version_state=unchecked
  [ -n "$latest" ] && version_state=$(version_verdict "$ver" "$latest")

  # --- Verdict: a finding wins; "current" only when every applicable check ran ---
  if [ "${osv:-0}" -gt 0 ]; then
    status="cve-warning"
  elif [ "$version_state" = update-available ]; then
    status="update-available"
  elif [ "$NET" -eq 1 ] && [ "$osv_ok" -eq 1 ] && [ -n "$latest" ]; then
    status="current"
  else
    status="unchecked"
  fi

  # --- Local integrity: has the vendored copy changed since it was recorded? ---
  if [ -z "$loc" ]; then
    local_state=unknown
  elif [ ! -e "$ROOT/$loc" ]; then
    local_state=missing
  elif [ -z "$sum" ]; then
    local_state=untracked
  elif h=$(cd "$ROOT" && location_hash "$loc"); then
    [ "sha256:$h" = "$sum" ] && local_state=unchanged || local_state=modified
  else
    local_state=unknown
  fi

  echo "ENTRY|$name|$ver|${latest:-unknown}|${osv:-0}|$status|$local_state|$version_state"

  # --- Upstream copy: does the recorded Upstream-Path still hold these bytes? ---
  case "$src" in
    *github.com/*)
      if [ -n "$upath" ] && [ -n "$loc" ] && [ -f "$ROOT/$loc" ]; then
        up=unchecked
        ownerrepo=$(printf '%s' "$src" | sed -E 's|.*github\.com/([^/ ]+/[^/ ]+).*|\1|; s|\.git$||')
        if [ "$NET" -eq 1 ] && [ -n "$ownerrepo" ] && [ -n "$sum" ]; then
          tmpf=$(mktemp "${TMPDIR:-/tmp}/lifeline-up.XXXXXX")
          code=$(curl -sL --max-time 20 -o "$tmpf" -w '%{http_code}' \
            "https://raw.githubusercontent.com/$ownerrepo/HEAD/$upath" 2>/dev/null) || code=000
          case "$code" in
            200) [ "sha256:$(sha_stdin < "$tmpf")" = "$sum" ] && up=identical || up=differs ;;
            404) up=missing ;;
          esac
          rm -f "$tmpf"
        fi
        echo "UPSTREAM|$name|$upath|$up"
      fi
      ;;
  esac
done
