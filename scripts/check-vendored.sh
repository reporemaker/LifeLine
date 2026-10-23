#!/usr/bin/env bash
# lifeline: check every VENDORED.md ledger entry for upstream updates and known CVEs.
# Usage: check-vendored.sh [project-root]
# Output lines:
#   NOLEDGER|<path>                                    no ledger file — nothing to check
#   OFFLINE|<reason>                                   remote checks skipped, say so in the report
#   ENTRY|name|recorded|latest-upstream|osv-hits|status
# status: current | update-available | cve-warning | unchecked
#   current   = every check that applies to the entry ran and found nothing
#   unchecked = offline, or a check that applies could not run (non-GitHub Source,
#               OSV request failed) - never reported as current
# The script only reads; updating Last-Checked/Status in VENDORED.md is the skill's job.
set -u

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

awk '
  function flush() { if (name != "") print name "|" eco "|" pkg "|" ver "|" src }
  /^## /   { flush(); name = substr($0, 4); eco = ""; pkg = ""; ver = ""; src = "" }
  /^- Source:/       { sub(/^- Source:[ \t]*/, "");       sub(/[ \t]+#.*$/, ""); src = $0 }
  /^- Ecosystem:/    { sub(/^- Ecosystem:[ \t]*/, "");    sub(/[ \t]+#.*$/, ""); eco = $0 }
  /^- Package-Name:/ { sub(/^- Package-Name:[ \t]*/, ""); sub(/[ \t]+#.*$/, ""); pkg = $0 }
  /^- Version:/      { sub(/^- Version:[ \t]*/, "");      sub(/[ \t]+#.*$/, ""); ver = $0 }
  END { flush() }
' "$LEDGER" | while IFS='|' read -r name eco pkg ver src; do
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

  # --- Upstream version lookup (GitHub sources, best effort, unauthenticated) ---
  latest=""
  case "$src" in
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

  echo "ENTRY|$name|$ver|${latest:-unknown}|${osv:-0}|$status"
done
