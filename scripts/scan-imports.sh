#!/usr/bin/env bash
# LifeLine: scan the raw import + external URL surface of a project.
# Usage: scan-imports.sh [project-root]
# Output (tab-separated): LANG<TAB>module<TAB>occurrence-count, plus URL/ASSET lines.
# This is a raw surface scan: the skill interprets and filters the output.
set -u

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "ERROR|cannot access $ROOT" >&2; exit 1; }

EX="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=vendor --exclude-dir=.venv --exclude-dir=venv --exclude-dir=dist --exclude-dir=build --exclude-dir=target --exclude-dir=__pycache__"

count() { sort | uniq -c | sort -rn | awk -v tag="$1" '{printf "%s\t%s\t%s\n", tag, $2, $1}'; }

# Type declaration files (*.d.ts) are mostly generated (wrangler types, codegen) and
# full of doc links and example imports - they would drown the real surface.

# JavaScript / TypeScript: external = not starting with . / # or node:
grep -rEhoI $EX --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' \
  --include='*.mjs' --include='*.cjs' --include='*.vue' --include='*.svelte' --exclude='*.d.ts' \
  -e "from[[:space:]]+['\"][^'\"]+['\"]" -e "require\(['\"][^'\"]+['\"]\)" \
  -e "import\(['\"][^'\"]+['\"]\)" \
  -e "^[[:space:]]*import[[:space:]]+['\"][^'\"]+['\"]" . 2>/dev/null |
  sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" |
  grep -Ev '^(\.|/|#|node:)' | grep -Ev '^$' |
  sed -E 's|^(@[^/]+/[^/]+).*|\1|; s|^([^@][^/]*)/.*|\1|' | count JS

# Python: top-level module of import/from lines
grep -rEhoI $EX --include='*.py' \
  -e '^[[:space:]]*import[[:space:]]+[A-Za-z0-9_.]+' \
  -e '^[[:space:]]*from[[:space:]]+[A-Za-z0-9_.]+[[:space:]]+import' . 2>/dev/null |
  sed -E 's/^[[:space:]]*(from|import)[[:space:]]+([A-Za-z0-9_.]+).*/\2/' |
  cut -d. -f1 | grep -Ev '^_*$' | count PY

# Go: quoted import paths that contain a domain
grep -rEhoI $EX --include='*.go' -e '"[a-z0-9.-]+\.[a-z]{2,}/[^"]+"' . 2>/dev/null |
  tr -d '"' | count GO

# Rust: use/extern crate roots (std/core/self filtered)
grep -rEhoI $EX --include='*.rs' \
  -e '^[[:space:]]*use[[:space:]]+[a-z_][a-z0-9_]*' -e 'extern crate [a-z_][a-z0-9_]*' . 2>/dev/null |
  sed -E 's/.*(use|crate)[[:space:]]+([a-z_][a-z0-9_]*).*/\2/' |
  grep -Ev '^(crate|self|super|std|core|alloc)$' | count RS

# Java / Kotlin: first two package segments (java./javax./kotlin. filtered)
grep -rEhoI $EX --include='*.java' --include='*.kt' \
  -e '^import[[:space:]]+[a-z][A-Za-z0-9_.]+' . 2>/dev/null |
  sed -E 's/^import[[:space:]]+([a-z][a-z0-9_]*\.[a-z0-9_]+).*/\1/' |
  grep -Ev '^(java\.|javax\.|kotlin\.)' | count JAVA

# Ruby: require (require_relative excluded)
grep -rEhoI $EX --include='*.rb' \
  -e "^[[:space:]]*require[[:space:]]+['\"][^'\"]+['\"]" . 2>/dev/null |
  sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" | grep -Ev '^\.' | count RB

# PHP: top vendor namespace of use statements
grep -rEhoI $EX --include='*.php' -e '^use[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\\' . 2>/dev/null |
  sed -E 's/^use[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' | count PHP

# Swift: imported modules (Apple frameworks filtered)
grep -rEhoI $EX --include='*.swift' -e '^import[[:space:]]+[A-Za-z0-9_]+' . 2>/dev/null |
  sed -E 's/^import[[:space:]]+([A-Za-z0-9_]+).*/\1/' |
  grep -Ev '^(Foundation|UIKit|SwiftUI|AppKit|Combine|CoreData|CoreGraphics|CoreLocation|Dispatch|XCTest|Swift)$' | count SWIFT

# External hosts referenced anywhere in text files (lock/vendor/doc noise excluded)
grep -rEhoI $EX \
  --exclude='*.lock' --exclude='package-lock.json' --exclude='*.sum' --exclude='*.md' \
  --exclude='*.svg' --exclude='*.map' --exclude='*.min.js' --exclude='*.min.css' --exclude='*.d.ts' \
  -e 'https?://[A-Za-z0-9.-]+\.[A-Za-z]{2,}' . 2>/dev/null |
  sed -E 's|^https?://||' | count URL

# Full URLs of fetched assets (CDN scripts, fonts, models, archives)
grep -rEhoI $EX \
  --exclude='*.lock' --exclude='package-lock.json' --exclude='*.sum' --exclude='*.map' \
  -e "https?://[^\"'<> )]+\.(js|css|woff2?|ttf|otf|onnx|gguf|safetensors|pt|bin|zip|tar\.gz|tgz)" . 2>/dev/null |
  sort -u | awk '{printf "ASSET\t%s\t1\n", $0}'
