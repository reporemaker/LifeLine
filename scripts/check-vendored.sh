#!/usr/bin/env bash
# LifeLine: check every VENDORED.md ledger entry for upstream updates and known CVEs.
# Usage: check-vendored.sh [project-root]
#        check-vendored.sh --hash <project-root> <location>   checksum for a new entry
# Output lines:
#   NOLEDGER|<path>                                    no ledger file — nothing to check
#   OFFLINE|<reason>                                   remote checks skipped, say so in the report
#   ENTRY|name|recorded|latest-upstream|osv-hits|status|local
#   HASH|<location>|sha256:<hex>                       (--hash mode)
# status: current | update-available | cve-warning | unchecked
#   current   = every check that applies to the entry ran and found nothing
#   unchecked = offline, or a check that applies could not run (no registry identity
#               and no GitHub Source, OSV request failed) - never reported as current
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
if command -v curl >/dev/null 2>&1; then
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
  function flush() { if (name != "") print name "|" eco "|" pkg "|" ver "|" src "|" loc "|" sum }
  /^## /   { flush(); name = substr($0, 4); eco = ""; pkg = ""; ver = ""; src = ""; loc = ""; sum = "" }
  /^- Location:/     { sub(/^- Location:[ \t]*/, "");     sub(/[ \t]+#.*$/, ""); loc = $0 }
  /^- Checksum:/     { sub(/^- Checksum:[ \t]*/, "");     sub(/[ \t]+#.*$/, ""); sum = $0 }
  /^- Source:/       { sub(/^- Source:[ \t]*/, "");       sub(/[ \t]+#.*$/, ""); src = $0 }
  /^- Ecosystem:/    { sub(/^- Ecosystem:[ \t]*/, "");    sub(/[ \t]+#.*$/, ""); eco = $0 }
  /^- Package-Name:/ { sub(/^- Package-Name:[ \t]*/, ""); sub(/[ \t]+#.*$/, ""); pkg = $0 }
  /^- Version:/      { sub(/^- Version:[ \t]*/, "");      sub(/[ \t]+#.*$/, ""); ver = $0 }
  END { flush() }
' "$LEDGER" | while IFS='|' read -r name eco pkg ver src loc sum; do
  [ -z "$name" ] && continue

  # --- OSV vulnerability lookup (only for registry-identified entries) ---
  osv=0
  osv_ok=1
  if [ -n "$pkg" ] && [ "$pkg" != "none" ] && [ -n "$eco" ] && [ "$eco" != "none" ]; then
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

  # --- Verdict: a finding wins; "current" only when every applicable check ran ---
  if [ "${osv:-0}" -gt 0 ]; then
    status="cve-warning"
  elif [ -n "$latest" ] && [ "${latest#v}" != "${ver#v}" ]; then
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

  echo "ENTRY|$name|$ver|${latest:-unknown}|${osv:-0}|$status|$local_state"
done
