#!/usr/bin/env bash
# LifeLine: how alive is a dependency upstream? Latest release, its age, deprecation,
# maintainers, source repo, archived flag, install-time scripts.
# Usage: upstream-health.sh <ecosystem> <package>
#   ecosystem: npm | PyPI | crates.io | Go | Maven | NuGet  (OSV names, any case)
# Output lines:
#   OFFLINE|<reason>
#   UNSUPPORTED|<ecosystem>|<package>
#   HEALTH|eco|pkg|latest|published|age-days|deprecated|maintainers|repo|archived|install-scripts|licenses|maintainer-names|publisher
#     maintainer-names: npm account names, sorted, ";"-joined (never emails)
#     publisher: the npm account that published the latest version
# Unknown fields are "unknown", never guessed. Sources: api.deps.dev (all ecosystems),
# registry.npmjs.org (npm only: maintainers, install scripts), api.github.com (archived).
# Set GITHUB_TOKEN to lift GitHub's 60 requests/hour anonymous limit.
set -u

ECO="${1:-}"
PKG="${2:-}"
[ -n "$ECO" ] && [ -n "$PKG" ] || { echo "usage: upstream-health.sh <ecosystem> <package>" >&2; exit 2; }

eco_lc=$(printf '%s' "$ECO" | tr 'A-Z' 'a-z')
case "$eco_lc" in
  npm) SYS=npm ;;
  pypi) SYS=pypi ;;
  crates.io|cargo) SYS=cargo ;;
  go|golang) SYS=go ;;
  maven) SYS=maven ;;
  nuget) SYS=nuget ;;
  *) echo "UNSUPPORTED|$ECO|$PKG"; exit 0 ;;
esac

if ! command -v curl >/dev/null 2>&1 || ! curl -s --max-time 6 -o /dev/null "https://api.deps.dev" 2>/dev/null; then
  echo "OFFLINE|network unavailable or curl missing - upstream health not checked"
  exit 0
fi

# Percent-encode for a URL path segment (scoped npm names, Go module paths, Maven g:a).
urlenc() { printf '%s' "$1" | sed 's/%/%25/g; s/@/%40/g; s|/|%2F|g; s/:/%3A/g; s/ /%20/g'; }

# Days between an ISO date (YYYY-MM-DD) and today; BSD date first, then GNU.
age_days() {
  then=$(date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null) || { echo unknown; return; }
  echo $(( ( $(date +%s) - then ) / 86400 ))
}

gh_get() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sL --max-time 10 -H "Authorization: Bearer $GITHUB_TOKEN" "$1" 2>/dev/null
  else
    curl -sL --max-time 10 "$1" 2>/dev/null
  fi
}

ENC=$(urlenc "$PKG")
pkg_json=$(curl -s --max-time 15 "https://api.deps.dev/v3/systems/$SYS/packages/$ENC" 2>/dev/null)

# The default version is the one the registry hands out ("latest" on npm).
latest=$(printf '%s' "$pkg_json" |
  grep -oE '"version":"[^"]*"\}(,"publishedAt":"[^"]*")?,"isDefault":true' | head -1 |
  sed -E 's/^"version":"([^"]*)".*/\1/')
[ -n "$latest" ] || latest=unknown

published=unknown; age=unknown; deprecated=no; licenses=unknown; repo=unknown
if [ "$latest" != unknown ]; then
  ver_json=$(curl -s --max-time 15 "https://api.deps.dev/v3/systems/$SYS/packages/$ENC/versions/$(urlenc "$latest")" 2>/dev/null)
  published=$(printf '%s' "$ver_json" | sed -n 's/.*"publishedAt":"\([0-9-]*\)T.*/\1/p' | head -1)
  [ -n "$published" ] && age=$(age_days "$published") || published=unknown
  if printf '%s' "$ver_json" | grep -q '"isDeprecated":true'; then
    reason=$(printf '%s' "$ver_json" | sed -n 's/.*"deprecatedReason":"\([^"]*\)".*/\1/p' | head -1)
    deprecated="yes${reason:+: $reason}"
  fi
  licenses=$(printf '%s' "$ver_json" | sed -n 's/.*"licenses":\[\([^]]*\)\].*/\1/p' | tr -d '"' | head -1)
  [ -n "$licenses" ] || licenses=unknown
  repo=$(printf '%s' "$ver_json" |
    grep -oE '"projectKey":\{"id":"[^"]*"\},"relationProvenance":"[^"]*","relationType":"SOURCE_REPO"' | head -1 |
    sed -E 's/^"projectKey":\{"id":"([^"]*)".*/\1/')
  [ -n "$repo" ] || repo=unknown
fi

# npm only: maintainer count and install-time scripts, from the published manifest.
maintainers=unknown; install=unknown; names=unknown; publisher=unknown
if [ "$SYS" = npm ]; then
  man=$(curl -s --max-time 15 "https://registry.npmjs.org/$(printf '%s' "$PKG" | sed 's|/|%2F|')/latest" 2>/dev/null)
  if printf '%s' "$man" | grep -q '"name"'; then
    m=$(printf '%s' "$man" | sed -n 's/.*"maintainers":\[\([^]]*\)\].*/\1/p' | grep -o '"name"' | wc -l | tr -d ' \t')
    [ -n "$m" ] && [ "$m" -gt 0 ] && maintainers=$m
    n=$(printf '%s' "$man" | sed -n 's/.*"maintainers":\[\([^]]*\)\].*/\1/p' |
      grep -oE '"name":"[^"]*"' | sed 's/"name":"//; s/"$//' | LC_ALL=C sort -u | tr '\n' ';' | sed 's/;$//')
    [ -n "$n" ] && names=$n
    u=$(printf '%s' "$man" | sed -n 's/.*"_npmUser":{"name":"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$u" ] && publisher=$u
    scripts=$(printf '%s' "$man" | sed -n 's/.*"scripts":{\([^}]*\)}.*/\1/p')
    install=$(printf '%s' "$scripts" | grep -oE '"(preinstall|install|postinstall)"' | tr -d '"' | tr '\n' ',' | sed 's/,$//')
    [ -n "$install" ] || install=none
  fi
fi

# GitHub-hosted source: archived flag (archived = upstream officially stopped).
archived=unknown
case "$repo" in
  github.com/*/*)
    rj=$(gh_get "https://api.github.com/repos/${repo#github.com/}")
    if printf '%s' "$rj" | grep -q '"archived": *true'; then archived=yes
    elif printf '%s' "$rj" | grep -q '"archived": *false'; then archived=no
    fi
    ;;
esac

echo "HEALTH|$ECO|$PKG|$latest|$published|$age|$deprecated|$maintainers|$repo|$archived|$install|$licenses|$names|$publisher"
