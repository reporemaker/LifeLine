#!/usr/bin/env bash
# LifeLine: measure an installed dependency - how much code it is, how much of it is
# reachable from its entry point, and how many packages it drags in.
# Usage: measure-package.sh <project-root> <package>
# Output lines:
#   NOTFOUND|<package>|<reason>
#   SIZE|pkg|version|ecosystem|code-files|code-lines|entry|reachable-files|reachable-lines|direct-deps|transitive-deps|install-scripts
#   TRANSITIVE|pkg|name@version          one line per package it pulls in (npm)
# "Reachable" follows relative require/import from the entry file only - file level, not
# function level. Dynamic requires and package "exports" maps are not followed; numbers
# are a floor for what vendoring would have to copy, not a ceiling.
# Reads installed files only (node_modules / site-packages); never installs anything.
set -u

ROOT="${1:-}"
PKG="${2:-}"
[ -n "$ROOT" ] && [ -n "$PKG" ] || { echo "usage: measure-package.sh <project-root> <package>" >&2; exit 2; }
cd "$ROOT" 2>/dev/null || { echo "NOTFOUND|$PKG|cannot access $ROOT"; exit 0; }
ROOTABS=$(pwd -P)

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lifeline.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# One path per line in; paths may contain spaces (NUL-separated for xargs). The sum of
# per-file "wc -l" equals "wc -l" of the concatenation: both count newline characters.
lines_of() { [ -s "$1" ] && tr '\n' '\0' < "$1" | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ' || echo 0; }

# --- npm ---------------------------------------------------------------------
# Dependency names of an installed package (node if present, awk otherwise).
deps_of() {
  if command -v node >/dev/null 2>&1; then
    node -e 'try{const p=require(process.argv[1]);for(const k of Object.keys(p.dependencies||{}))console.log(k)}catch(e){}' "$(cd "$1" && pwd -P)/package.json" 2>/dev/null
  else
    tr -d '\n' < "$1/package.json" | sed -n 's/.*"dependencies"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' |
      tr ',' '\n' | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p'
  fi
}

# Node resolution: nearest node_modules/<dep> walking up from the requiring package.
resolve_dep() {
  dir="$1"
  while :; do
    [ -f "$dir/node_modules/$2/package.json" ] && { echo "$dir/node_modules/$2"; return; }
    [ "$dir" = "." ] && return
    case "$dir" in */node_modules/*) dir="${dir%/node_modules/*}" ;; *) dir="." ;; esac
  done
}

json_field() { sed -n "s/^[[:space:]]*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }

# Absolute, symlink-free path, so "a/./b" and "a/x/../b" count as one file.
canon() { (cd "$(dirname "$1")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")"); }

# Resolve a relative specifier the way Node does for files; code files only
# (a require of ./package.json or ./data.json is not code to vendor).
resolve_file() {
  for c in "$1" "$1.js" "$1.cjs" "$1.mjs" "$1.ts" "$1/index.js" "$1/index.cjs" "$1/index.mjs"; do
    case "$c" in *.d.ts) continue ;; *.js|*.cjs|*.mjs|*.ts) ;; *) continue ;; esac
    [ -f "$c" ] && { canon "$c"; return; }
  done
}

# Entry file: Node's own resolver first (understands "exports" maps), then "main".
resolve_entry() {
  if command -v node >/dev/null 2>&1; then
    e=$(node -e 'try{console.log(require.resolve(process.argv[1],{paths:[process.argv[2]]}))}catch(e){}' "$PKG" "$ROOTABS" 2>/dev/null)
    [ -n "$e" ] || e=$(cd "$ROOTABS" && node --input-type=module -e 'try{console.log(new URL(import.meta.resolve(process.argv[1])).pathname)}catch(e){}' "$PKG" 2>/dev/null)
    case "$e" in "$ROOTABS"/*) [ -f "$e" ] && { canon "$e"; return; } ;; esac
  fi
  main=$(json_field "$P/package.json" main)
  e=$(resolve_file "$P/${main:-index}")
  [ -n "$e" ] || e=$(resolve_file "$P/index")
  echo "$e"
}

measure_npm() {
  P="node_modules/$PKG"
  ver=$(json_field "$P/package.json" version)

  find "$P" \( -name node_modules -o -name test -o -name tests -o -name __tests__ -o -name example -o -name examples \) -prune -o \
    -type f \( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' -o -name '*.ts' \) \
    ! -name '*.d.ts' ! -name '*.min.js' ! -name '*.map' -print 2>/dev/null | sort > "$TMP/all"
  files=$(wc -l < "$TMP/all" | tr -d ' ')
  lines=$(lines_of "$TMP/all")

  entry=$(resolve_entry)
  : > "$TMP/seen"
  if [ -n "$entry" ]; then
    echo "$entry" > "$TMP/queue"
    while [ -s "$TMP/queue" ]; do
      f=$(head -1 "$TMP/queue"); sed -i.bak '1d' "$TMP/queue"
      grep -qxF "$f" "$TMP/seen" && continue
      echo "$f" >> "$TMP/seen"
      d=$(dirname "$f")
      grep -oE "(require\(|from[[:space:]]+|import\()[[:space:]]*['\"]\.{1,2}/[^'\"]+['\"]" "$f" 2>/dev/null |
        sed -E "s/.*['\"](\.[^'\"]+)['\"].*/\1/" | while IFS= read -r spec; do
          r=$(resolve_file "$d/$spec")
          [ -n "$r" ] && echo "$r" >> "$TMP/queue"
        done
    done
  fi
  rfiles=$(wc -l < "$TMP/seen" | tr -d ' ')
  rlines=$(lines_of "$TMP/seen")

  direct=$(deps_of "$P" | grep -c .)
  # Transitive closure over installed packages.
  : > "$TMP/tseen"
  echo "$P" > "$TMP/tq"
  while [ -s "$TMP/tq" ]; do
    cur=$(head -1 "$TMP/tq"); sed -i.bak '1d' "$TMP/tq"
    deps_of "$cur" | while IFS= read -r dep; do
      loc=$(resolve_dep "$cur" "$dep")
      [ -n "$loc" ] || { echo "MISSING $dep" >> "$TMP/tseen"; continue; }
      grep -qxF "$loc" "$TMP/tseen" && continue
      echo "$loc" >> "$TMP/tseen"
      echo "$loc" >> "$TMP/tq"
    done
  done
  trans=$(grep -vc '^MISSING ' "$TMP/tseen")

  inst=$(tr -d '\n' < "$P/package.json" | sed -n 's/.*"scripts"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p' |
    grep -oE '"(preinstall|install|postinstall)"' | tr -d '"' | tr '\n' ',' | sed 's/,$//')

  PABS=$(cd "$P" && pwd -P)
  echo "SIZE|$PKG|${ver:-unknown}|npm|$files|$lines|${entry#$PABS/}|$rfiles|$rlines|$direct|$trans|${inst:-none}"
  grep -v '^MISSING ' "$TMP/tseen" | while IFS= read -r loc; do
    echo "TRANSITIVE|$PKG|$(json_field "$loc/package.json" name)@$(json_field "$loc/package.json" version)"
  done
  grep '^MISSING ' "$TMP/tseen" | sort -u | while read -r _ dep; do
    echo "TRANSITIVE|$PKG|$dep@not-installed"
  done
}

# --- Python ------------------------------------------------------------------
measure_py() {
  py=""
  for c in .venv/bin/python venv/bin/python python3; do
    command -v "$c" >/dev/null 2>&1 && { py="$c"; break; }
  done
  [ -n "$py" ] || { echo "NOTFOUND|$PKG|not in node_modules and no Python interpreter"; return; }
  # -I: isolated mode, so nothing in the audited project is imported by accident.
  "$py" -I - "$PKG" <<'EOF'
import sys, re
from importlib import metadata
name = sys.argv[1]
try:
    dist = metadata.distribution(name)
except metadata.PackageNotFoundError:
    print(f"NOTFOUND|{name}|not installed for this interpreter"); sys.exit(0)
if dist.files is None:
    files = lines = "unknown"  # no RECORD (e.g. installed by a system package manager)
else:
    files, lines = 0, 0
for f in dist.files or []:
    if str(f).endswith(".py") and "/tests/" not in f"/{f}":
        try:
            lines += sum(1 for _ in open(f.locate(), encoding="utf-8", errors="ignore")); files += 1
        except OSError:
            pass
reqs = [r for r in (dist.requires or []) if "extra ==" not in r]
direct = len(reqs)
seen, queue = set(), [re.split(r"[ ;<>=!~\[(]", r)[0] for r in reqs]
while queue:
    n = queue.pop().lower()
    if n in seen:
        continue
    seen.add(n)
    try:
        d = metadata.distribution(n)
        queue += [re.split(r"[ ;<>=!~\[(]", r)[0] for r in (d.requires or []) if "extra ==" not in r]
    except metadata.PackageNotFoundError:
        pass
print(f"SIZE|{name}|{dist.version}|PyPI|{files}|{lines}|n/a|n/a|n/a|{direct}|{len(seen)}|n/a")
for n in sorted(seen):
    try:
        print(f"TRANSITIVE|{name}|{n}@{metadata.version(n)}")
    except metadata.PackageNotFoundError:
        print(f"TRANSITIVE|{name}|{n}@not-installed")
EOF
}

if [ -f "node_modules/$PKG/package.json" ]; then
  measure_npm
else
  measure_py
fi
