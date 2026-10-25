# Ecosystem Reference

Per-ecosystem instructions for building the dependency inventory. For every ecosystem:
**preferred path** (the ecosystem's own tool, if installed) and **fallback path**
(parse manifest/lock files directly - always works, never requires installing anything).
Never install a tool just to run the audit; note its absence in the report instead.

Common rule for all ecosystems: prune `node_modules`, `.git`, `vendor`, `venv`/`.venv`,
`dist`, `build`, `target`, `__pycache__` from every scan.

## JavaScript / TypeScript (npm, yarn, pnpm, bun)

- **Manifests**: `package.json` (deps in `dependencies`, `devDependencies`,
  `peerDependencies`, `optionalDependencies`). Workspaces field → monorepo, walk packages.
- **Locks**: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock` (text, Bun 1.2+),
  `bun.lockb` (older binary - use manifest).
- **Preferred**: `npm ls --all --json` (or `pnpm ls -r --json`, `yarn list --json`).
  CVE check if available: `npm audit --json`.
- **Fallback**: direct deps from `package.json`; transitive count and pinned versions from
  the lock file (`package-lock.json` is JSON - read `packages` keys).
- **Import patterns**: `import x from 'pkg'`, `require('pkg')`, `import('pkg')`.
  Module is external when it does not start with `./`, `../`, `/`, `#`, or a `paths` alias.
  Scoped packages: `@scope/name` (first two segments). Node builtins (`fs`, `path`,
  `node:*`) are not external dependencies.
- **Unpinned signals**: `*`, `latest`, `>=`, git/URL deps in `package.json`.

## Python (pip, poetry, uv, pipenv)

- **Manifests**: `pyproject.toml` (`dependencies` and `[project.optional-dependencies]` under
  `[project]`, `[tool.poetry.dependencies]`, `[dependency-groups]`),
  `requirements*.txt`, `setup.py`/`setup.cfg`, `Pipfile`.
- **Locks**: `poetry.lock`, `uv.lock`, `Pipfile.lock`, fully-pinned `requirements.txt`.
- **Preferred**: `pip list --format=json` in the project venv; tree: `pipdeptree --json`
  if installed. CVE check if available: `pip-audit`.
- **Fallback**: parse manifests; `poetry.lock`/`uv.lock` are TOML - `[[package]]` blocks
  give the full transitive set with versions.
- **Import patterns**: `^import pkg`, `^from pkg import`. Map import name → package name
  cautiously (e.g. `import cv2` = `opencv-python`, `import PIL` = `Pillow`); when unsure,
  say so in the report. Stdlib modules are not external.
- **Unpinned signals**: bare names in `requirements.txt`, `*` versions, missing lock.

## Go

- **Manifest**: `go.mod` (`require` blocks; `// indirect` marks transitive).
- **Lock**: `go.sum`.
- **Preferred**: `go list -m all`; graph: `go mod graph`.
- **Fallback**: `go.mod` alone is sufficient - it lists everything with versions.
- **Import patterns**: quoted paths containing a dot-domain (`"github.com/x/y"`) inside
  `import` statements/blocks. Stdlib (no domain) is not external.

## Rust

- **Manifest**: `Cargo.toml` (`[dependencies]`, `[dev-dependencies]`, `[build-dependencies]`).
- **Lock**: `Cargo.lock` (full transitive set as `[[package]]` blocks).
- **Preferred**: `cargo tree`. CVE check if available: `cargo audit`.
- **Fallback**: `Cargo.lock` parse.
- **Import patterns**: `use cratename::…`, `extern crate cratename`. Crate names use `_`
  where the registry name may use `-`.

## Java / Kotlin (Maven, Gradle)

- **Manifests**: `pom.xml` (`<dependencies>`), `build.gradle`/`build.gradle.kts`
  (`implementation`, `api`, `compileOnly`, plugin blocks).
- **Locks**: `gradle.lockfile` per module and `settings-gradle.lockfile` /
  `buildscript-gradle.lockfile` (when dependency locking is on); Maven has none
  (versions in pom/parent).
- **Snapshot**: `snapshot-state.sh` reads Gradle lock files itself (plain awk, no Gradle
  needed). Lines are `group:name:version=config1,config2,…`; all lock files of one build
  (the directory with the settings script) form one project. Scope: a release runtime
  classpath (`prodReleaseRuntimeClasspath`, `runtimeClasspath` in plain JVM builds)
  ships to users; debug, test, lint, compiler and plugin classpaths are dev. Direct =
  named in a `build.gradle(.kts)`, as a version-catalog accessor (`libs.compose.ui`,
  bundles too, from `gradle/*.versions.toml`) or a literal `"group:name:version"`.
  Packages a plugin adds (Kotlin's `kotlin-stdlib`, AGP's `viewbinding`) are named
  nowhere and count as transitive. Locks carry no licences: direct rows get the
  registry licence from deps.dev, transitive rows stay `-`.
- **Integrity**: `gradle/verification-metadata.xml` (`--write-verification-metadata
  sha256`) pins every artifact. Regenerating it over an existing file keeps the entries
  of replaced versions; delete it first to drop them.
- **Toolchain** (`TOOLCHAIN` in find-manifests): `gradle/wrapper/gradle-wrapper.properties`
  should carry `distributionSha256Sum`. `gradle/gradle-daemon-jvm.properties` with
  `toolchainUrl.*`, the foojay resolver plugin or `org.gradle.java.installations.auto-download`
  let the build download a JDK without a pinned checksum; Android Studio writes the
  daemon JVM file back when its Gradle JDK is set to "daemon JVM criteria".
- **Preferred**: `mvn dependency:tree` / `gradle dependencies` (only if wrapper or tool present).
- **Fallback**: parse pom/gradle files; note that transitive resolution without the tool
  is incomplete; say so in the report.
- **Import patterns**: `import com.foo.bar.Baz;` - map top packages to artifacts where
  obvious; otherwise report at package-prefix level.

## .NET

- **Manifests**: `*.csproj` (`<PackageReference Include=… Version=…>`), `packages.config`,
  `Directory.Packages.props`.
- **Lock**: `packages.lock.json` (if enabled).
- **Preferred**: `dotnet list package --include-transitive`.
- **Fallback**: csproj parse (XML, trivial).
- **Import patterns**: `using Namespace;` - map to packages where obvious.

## PHP (Composer)

- **Manifest**: `composer.json` (`require`, `require-dev`).
- **Lock**: `composer.lock` (full transitive set, JSON).
- **Preferred**: `composer show --tree`.
- **Fallback**: `composer.lock` parse.
- **Import patterns**: `use Vendor\Package\…;` - vendor prefix maps to the package.

## Ruby

- **Manifest**: `Gemfile`. **Lock**: `Gemfile.lock` (full set, plain text).
- **Preferred**: `bundle list`.
- **Fallback**: `Gemfile.lock` parse (`GEM > specs:` section).
- **Import patterns**: `require 'gem'` (exclude relative `require_relative`).

## Swift / iOS

- **Manifests**: `Package.swift` (`.package(url:…)`), `Podfile`.
  **Locks**: `Package.resolved`, `Podfile.lock`.
- **Fallback**: locks are JSON/YAML-ish, parse directly.
- **Import patterns**: `import ModuleName` (exclude Apple frameworks: UIKit, SwiftUI, Foundation…).

## Containers (external code too)

- **Files**: `Dockerfile*`, `*.dockerfile`, `docker-compose*.yml`, `.devcontainer/devcontainer.json`.
- **Extract**: every `FROM image:tag` (base images), `image:` in compose, `"image"` in
  devcontainer. `latest` or missing tag = unpinned → risk signal. `COPY --from=` registry
  refs and `ADD <url>` count as dependencies as well.

## CI / Build Pipeline (external code too)

- **Files**: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `.circleci/config.yml`,
  `azure-pipelines.yml`, `Jenkinsfile`, `bitbucket-pipelines.yml`.
- **Extract**: GitHub Actions `uses: owner/action@ref` (ref = branch/tag → unpinned risk;
  full commit SHA → pinned), GitLab `include:`/`image:`, orbs in CircleCI, `curl | bash`
  or `wget` install lines anywhere in CI (high-risk external fetch - always flag).

## Web Assets (external code too)

- **Where**: HTML/templates (`<script src=…>`, `<link href=…>`), CSS (`@import url(…)`,
  `url(…)` for fonts), lockless CDN pulls in JS (`fetch` of scripts).
- **Extract**: any absolute `https://` asset URL to a third-party host. Subresource
  integrity (`integrity=`) absent on a CDN script → risk signal (polyfill.io-class attacks).
- Downloaded models/datasets: URLs in scripts/makefiles pointing at model files
  (`.onnx`, `.gguf`, `.safetensors`, `.pt`, dataset archives).

## Other ecosystems (Dart/pubspec, Elixir/mix, …)

`find-manifests.sh` also surfaces manifests not detailed above. Apply the same generic
pattern: manifest = declared direct deps, lock = full pinned set, imports = grep the
language's import syntax. State in the report that the ecosystem was handled generically.

## Import-name ambiguity: honesty rule

When the import name → package mapping is uncertain, or a language's transitive set
cannot be resolved without its tool, the report must say exactly that in the
"Limits of This Analysis" section. An honest gap beats a confident guess.
