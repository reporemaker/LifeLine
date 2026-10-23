#!/usr/bin/env bash
# lifeline: discover every dependency surface in a project tree.
# Usage: find-manifests.sh [project-root]
# Output: CATEGORY<TAB>relative-path  (MANIFEST | LOCK | CI | CONTAINER | LEDGER)
set -u

ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "ERROR|cannot access $ROOT" >&2; exit 1; }

find . \
  \( -name node_modules -o -name .git -o -name vendor -o -name .venv -o -name venv \
     -o -name dist -o -name build -o -name target -o -name __pycache__ \) -prune -o \
  -type f \( \
     -name package.json -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml -o -name bun.lockb \
     -o -name pyproject.toml -o -name 'requirements*.txt' -o -name setup.py -o -name setup.cfg \
     -o -name Pipfile -o -name Pipfile.lock -o -name poetry.lock -o -name uv.lock \
     -o -name go.mod -o -name go.sum \
     -o -name Cargo.toml -o -name Cargo.lock \
     -o -name pom.xml -o -name 'build.gradle*' -o -name gradle.lockfile \
     -o -name '*.csproj' -o -name packages.config -o -name packages.lock.json -o -name Directory.Packages.props \
     -o -name composer.json -o -name composer.lock \
     -o -name Gemfile -o -name Gemfile.lock \
     -o -name Package.swift -o -name Package.resolved -o -name Podfile -o -name Podfile.lock \
     -o -name pubspec.yaml -o -name pubspec.lock -o -name mix.exs -o -name mix.lock \
     -o -name 'Dockerfile*' -o -name '*.dockerfile' \
     -o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' -o -name devcontainer.json \
     -o -name .gitlab-ci.yml -o -name azure-pipelines.yml -o -name Jenkinsfile \
     -o -name .travis.yml -o -name bitbucket-pipelines.yml \
     -o -path './.circleci/config.yml' -o -path '*/.circleci/config.yml' \
     -o -path './.github/workflows/*.yml' -o -path './.github/workflows/*.yaml' \
     -o -path '*/.github/workflows/*.yml' -o -path '*/.github/workflows/*.yaml' \
     -o -name VENDORED.md \
  \) -print 2>/dev/null | sort | while IFS= read -r f; do
  rel="${f#./}"
  base="${f##*/}"
  case "$rel" in
    .github/workflows/*|*/.github/workflows/*|.circleci/config.yml|*/.circleci/config.yml)
      printf 'CI\t%s\n' "$rel"; continue ;;
  esac
  case "$base" in
    .gitlab-ci.yml|azure-pipelines.yml|Jenkinsfile|.travis.yml|bitbucket-pipelines.yml)
      printf 'CI\t%s\n' "$rel" ;;
    Dockerfile*|*.dockerfile|docker-compose*|devcontainer.json)
      printf 'CONTAINER\t%s\n' "$rel" ;;
    package-lock.json|yarn.lock|pnpm-lock.yaml|bun.lockb|Pipfile.lock|poetry.lock|uv.lock|go.sum|Cargo.lock|gradle.lockfile|packages.lock.json|composer.lock|Gemfile.lock|Package.resolved|Podfile.lock|pubspec.lock|mix.lock)
      printf 'LOCK\t%s\n' "$rel" ;;
    VENDORED.md)
      printf 'LEDGER\t%s\n' "$rel" ;;
    *)
      printf 'MANIFEST\t%s\n' "$rel" ;;
  esac
done
