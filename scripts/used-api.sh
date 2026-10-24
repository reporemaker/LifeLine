#!/usr/bin/env bash
# LifeLine: which parts of a package does the project actually use?
# The input for "vendor only what is used": the exported names and members the
# project's own code touches, per file.
# Usage: used-api.sh <project-root> <package>
# Output lines:
#   USE|pkg|file|kind|symbol|count
#     kind: named (import {a} / const {a} = require) | default (the binding is called)
#           member (binding.member) | whole (binding passed around - every use unclear)
#   API|pkg|files|distinct-symbols
# JS/TS and Python. Static and per file: re-exports through the project's own modules
# and dynamic access (obj[name]) are not followed.
set -u

ROOT="${1:-}"
PKG="${2:-}"
[ -n "$ROOT" ] && [ -n "$PKG" ] || { echo "usage: used-api.sh <project-root> <package>" >&2; exit 2; }
cd "$ROOT" 2>/dev/null || { echo "ERROR|cannot access $ROOT" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lifeline.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

EX="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build --exclude-dir=target --exclude-dir=__pycache__"
# Regex-escaped package name (dots in lodash.get, slashes in @scope/name).
Q=$(printf '%s' "$PKG" | sed 's/[.[\*^$/]/\\&/g')

: > "$TMP/out"
emit() { echo "$1|$2|$3" >> "$TMP/out"; }   # file|kind|symbol

# Count binding.member uses and bare calls of one local binding in one flattened file.
members() {
  file="$1"; flat="$2"; b="$3"
  grep -oE "(^|[^A-Za-z0-9_\$.])$b\.[A-Za-z_\$][A-Za-z0-9_\$]*" "$flat" |
    sed -E "s/.*$b\.//" | while IFS= read -r m; do emit "$file" member "$m"; done
  n=$(grep -oE "(^|[^A-Za-z0-9_\$.])$b[[:space:]]*\(" "$flat" | wc -l | tr -d ' ')
  i=0; while [ "$i" -lt "$n" ]; do emit "$file" default "$b()"; i=$((i + 1)); done
  # Passed or stored as a value: neither called nor dotted.
  if grep -qE "(^|[^A-Za-z0-9_\$.])$b[[:space:]]*[,)\]}]" "$flat"; then emit "$file" whole "$b"; fi
}

# --- JavaScript / TypeScript --------------------------------------------------
grep -rlEI $EX --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' \
  --include='*.mjs' --include='*.cjs' --include='*.vue' --include='*.svelte' --exclude='*.d.ts' \
  -e "['\"]$Q(/[^'\"]*)?['\"]" . 2>/dev/null | sort | while IFS= read -r f; do
  file="${f#./}"
  # One line per file, comments left in: multi-line import lists become greppable.
  tr '\n' ' ' < "$f" > "$TMP/flat"
  SRC="['\"]$Q(/[^'\"]*)?['\"]"

  # import { a, b as c } from 'pkg'   /   import def, { a } from 'pkg'
  grep -oE "import[[:space:]]+(type[[:space:]]+)?([A-Za-z_\$][A-Za-z0-9_\$]*[[:space:]]*,[[:space:]]*)?\{[^}]*\}[[:space:]]*from[[:space:]]*$SRC" "$TMP/flat" |
    sed -E 's/.*\{([^}]*)\}.*/\1/' | tr ',' '\n' | sed -E 's/^[[:space:]]*(type[[:space:]]+)?//; s/[[:space:]]+as[[:space:]]+.*//; s/[[:space:]]*$//' |
    grep -E '^[A-Za-z_$]' | while IFS= read -r n; do emit "$file" named "$n"; done

  # const { a, b: c } = require('pkg')
  grep -oE "\{[^}]*\}[[:space:]]*=[[:space:]]*require\([[:space:]]*$SRC[[:space:]]*\)" "$TMP/flat" |
    sed -E 's/^\{([^}]*)\}.*/\1/' | tr ',' '\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*:.*//; s/[[:space:]]*$//' |
    grep -E '^[A-Za-z_$]' | while IFS= read -r n; do emit "$file" named "$n"; done

  # Local bindings that stand for the whole module (or its default export).
  {
    grep -oE "import[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*([[:space:]]*,[^;]*)?[[:space:]]+from[[:space:]]*$SRC" "$TMP/flat" |
      sed -E 's/^import[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*).*/\1/' | grep -v '^type$'
    grep -oE "import[[:space:]]+\*[[:space:]]+as[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*[[:space:]]+from[[:space:]]*$SRC" "$TMP/flat" |
      sed -E 's/.*as[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*).*/\1/'
    grep -oE "(const|let|var)[[:space:]]+[A-Za-z_\$][A-Za-z0-9_\$]*[[:space:]]*=[[:space:]]*require\([[:space:]]*$SRC[[:space:]]*\)" "$TMP/flat" |
      sed -E 's/^(const|let|var)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*).*/\2/'
  } | sort -u | while IFS= read -r b; do members "$file" "$TMP/flat" "$b"; done
done

# --- Python -----------------------------------------------------------------
PYMOD=$(printf '%s' "$PKG" | tr '-' '_' | tr 'A-Z' 'a-z')
grep -rlEI $EX --include='*.py' -e "^[[:space:]]*(from|import)[[:space:]]+$PYMOD([. ]|$)" . 2>/dev/null | sort | while IFS= read -r f; do
  file="${f#./}"
  # from pkg import a, b as c
  grep -E "^[[:space:]]*from[[:space:]]+$PYMOD(\.[A-Za-z0-9_.]+)?[[:space:]]+import[[:space:]]" "$f" |
    sed -E 's/.*import[[:space:]]+//; s/[()]//g' | tr ',' '\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]]+as[[:space:]]+.*//; s/[[:space:]]*$//' |
    grep -E '^[A-Za-z_]' | while IFS= read -r n; do emit "$file" named "$n"; done
  # import pkg [as alias]  ->  alias.member
  grep -E "^[[:space:]]*import[[:space:]]+$PYMOD([[:space:]]|$)" "$f" |
    sed -E "s/.*import[[:space:]]+$PYMOD([[:space:]]+as[[:space:]]+([A-Za-z_][A-Za-z0-9_]*))?.*/\2/" |
    while IFS= read -r alias; do
      tr '\n' ' ' < "$f" > "$TMP/flat"
      members "$file" "$TMP/flat" "${alias:-$PYMOD}"
    done
done

sort "$TMP/out" | uniq -c | while read -r c line; do
  file="${line%%|*}"; rest="${line#*|}"
  echo "USE|$PKG|$file|${rest%%|*}|${rest#*|}|$c"
done
nf=$(cut -d'|' -f1 "$TMP/out" | sort -u | grep -c .)
ns=$(cut -d'|' -f3 "$TMP/out" | sort -u | grep -c .)
echo "API|$PKG|$nf|$ns"
