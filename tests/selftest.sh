#!/usr/bin/env bash
# LifeLine self-test: small fixtures for the scripts whose mistakes would not show in a
# report (a project wrongly marked as not read, a run wrongly marked as partial, a wrong
# scope, a wrong version verdict). Offline, plain bash + standard Unix tools.
# Usage: tests/selftest.sh        prints one line per check, exits 1 if any check fails
set -u

S=$(cd "$(dirname "$0")/../scripts" && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/lifeline-selftest.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
export LIFELINE_OFFLINE=1
TAB=$(printf '\t')
fails=0

check() {   # check <name> <command...>: the command must succeed
  name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $name"; else echo "FAIL  $name"; fails=$((fails + 1)); fi
}
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }
hasnt() { ! printf '%s\n' "$1" | grep -qF -- "$2"; }

HEAD='project	ecosystem	package	version	scope	license	install	latest	published	deprecated	archived	maintainers	publisher	repo	vulns	local'
snap() {   # snap <file> <visibility> <date> <meta-lines> <rows>
  { printf '# LifeLine state v1\n# visibility: %s\n# generated: %s\n# project: t\n# deep: no\n# online: yes\n' "$2" "$3"
    [ -n "$4" ] && printf '%s\n' "$4"
    printf '%s\n' "$HEAD"
    [ -n "$5" ] && printf '%s\n' "$5"; } > "$1"
}
row() {    # row <package> <vulns>
  printf '.\tnpm\t%s\t1.0.0\tdirect-runtime\tMIT\tno\t1.0.0\t2026-01-01\tno\tno\tx\tx\tgithub.com/x/%s\t%s\t-' "$1" "$1" "$2"
}

# --- 1. A free-text "# limit:" line does not blind the project (issue #2) ---
mkdir -p "$T/d1"
snap "$T/d1/old.tsv" public 2026-10-24 "# limit: no lock file: rows built from a Gradle resolution" "$(row a -)"
snap "$T/d1/new.tsv" public 2026-10-25 "" "$(row a -)
$(row b -)"
out=$(bash "$S/diff-state.sh" "$T/d1/old.tsv" "$T/d1/new.tsv")
check "diff-state: free-text limit is a note, added package is found" has "$out" "|b|added|"

# --- 2. A real "<lock> not read" line still blinds that project ---
snap "$T/d1/old2.tsv" public 2026-10-24 "# limit: package-lock.json not read (node missing)" ""
out=$(bash "$S/diff-state.sh" "$T/d1/old2.tsv" "$T/d1/new.tsv")
check "diff-state: unread lock file hides additions" hasnt "$out" "|added|"
snap "$T/d1/old3.tsv" public 2026-10-24 "# limit: app/gradle.lockfile not read (lock file could not be parsed) [project: .]" ""
out=$(bash "$S/diff-state.sh" "$T/d1/old3.tsv" "$T/d1/new.tsv")
check "diff-state: [project: .] maps a module lock to the build root" hasnt "$out" "|added|"

# --- 3. timeline: free-text limit is no absence, real limit is ---
mkdir -p "$T/tl"
snap "$T/tl/2026-10-24.tsv" public 2026-10-24 "# limit: test configurations not read" "$(row a -)"
snap "$T/tl/2026-10-25.tsv" public 2026-10-25 "" "$(row a -)
$(row b -)"
out=$(bash "$S/timeline.sh" "$T/tl" public)
check "timeline: package missing behind a free note counts as absent" has "$out" "PRESENCE|.|b|2026-10-25|2026-10-25|1|1"

# --- 4. disclosure: a note that mentions OSV does not make the run partial ---
mkdir -p "$T/ds"
snap "$T/ds/2026-10-24.tsv" private 2026-10-24 "" "$(row a GHSA-test-0001)"
snap "$T/ds/2026-10-25.tsv" private 2026-10-25 "# note: OSV has no ecosystem for github rows (1) - their vulns are not collected
# limit: vendored rows from VENDORED.md: OSV has no github ecosystem" "$(row a none)"
out=$(bash "$S/disclosure.sh" "$T/ds")
check "disclosure: fixed advisory closes despite an OSV note" has "$out" "CLOSED|.|a|GHSA-test-0001|2026-10-24|2026-10-25|1"
snap "$T/ds/2026-10-25.tsv" private 2026-10-25 "# limit: OSV batch query failed - vulns not collected" "$(row a -)"
out=$(bash "$S/disclosure.sh" "$T/ds")
check "disclosure: OSV failure keeps the advisory open" has "$out" "OPEN|.|a|GHSA-test-0001"

# --- 5. Gradle lock reader (issue #1) ---
G="$T/gradle"; mkdir -p "$G/app" "$G/gradle"
printf 'rootProject.name = "t"\ninclude(":app")\n' > "$G/settings.gradle.kts"
cat > "$G/gradle/libs.versions.toml" <<'EOF'
[versions]
core = "1.2.0"

[libraries]
alpha-core = { group = "org.alpha", name = "core", version.ref = "core" }
beta_ui = { module = "org.beta:ui", version = "2.0.0" }
gamma = "org.gamma:gamma:3.0.0"
test-junit = { group = "junit", name = "junit", version = "4.13.2" }

[bundles]
ui = [
  "beta-ui",
]
EOF
cat > "$G/app/build.gradle.kts" <<'EOF'
dependencies {
    implementation(libs.alpha.core)
    implementation(libs.bundles.ui)
    implementation("org.literal:lit:1.0.0")
    testImplementation(libs.test.junit)
}
EOF
cat > "$G/app/gradle.lockfile" <<'EOF'
# This is a Gradle generated file for dependency locking.
org.alpha:core:1.2.0=prodReleaseRuntimeClasspath,prodDebugRuntimeClasspath
org.beta:ui:2.0.0=prodReleaseRuntimeClasspath
org.literal:lit:1.0.0=prodReleaseRuntimeClasspath
org.deep:dep:0.9.0=prodReleaseRuntimeClasspath
junit:junit:4.13.2=prodReleaseUnitTestRuntimeClasspath,prodDebugUnitTestRuntimeClasspath
org.lint:checks:1.0.0=lintChecksClasspath
empty=annotationProcessor
EOF
printf 'empty=incomingCatalogForLibs0\n' > "$G/settings-gradle.lockfile"
out=$(bash "$S/snapshot-state.sh" "$G")
scope() { printf '%s\n' "$out" | awk -F'\t' -v p="$1" '$3 == p { print $1 " " $5 }'; }
check "gradle: catalog accessor -> direct-runtime, build root as project" test "$(scope org.alpha:core)" = ". direct-runtime"
check "gradle: bundle member -> direct-runtime" test "$(scope org.beta:ui)" = ". direct-runtime"
check "gradle: literal coordinate -> direct-runtime" test "$(scope org.literal:lit)" = ". direct-runtime"
check "gradle: undeclared release package -> transitive-runtime" test "$(scope org.deep:dep)" = ". transitive-runtime"
check "gradle: unit-test classpath only -> direct-dev" test "$(scope junit:junit)" = ". direct-dev"
check "gradle: lint classpath -> transitive-dev" test "$(scope org.lint:checks)" = ". transitive-dev"
check "gradle: no 'not snapshotted' limit for a Gradle lock" hasnt "$out" "not snapshotted"
check "gradle: free text goes to a # note: line" has "$out" "# note: .: Gradle lock files read"

# --- 6. Vendored version verdicts ---
v() { bash "$S/check-vendored.sh" --compare "$1" "$2"; }
check "compare: release tag older than the copy -> ahead" test "$(v 9.000 v7.222)" = ahead
check "compare: v-prefix ignored -> current" test "$(v 1.15.2 v1.15.2)" = current
check "compare: numeric, not text (1.9 < 1.10)" test "$(v 1.9 1.10)" = update-available
check "compare: pre-release against its release -> update" test "$(v 1.0.0-rc1 1.0.0)" = update-available

# --- 7. Toolchain files are found ---
mkdir -p "$G/gradle/wrapper"; : > "$G/gradle/wrapper/gradle-wrapper.properties"; : > "$G/gradle/gradle-daemon-jvm.properties"
out=$(bash "$S/find-manifests.sh" "$G")
check "find-manifests: daemon JVM criteria is TOOLCHAIN" has "$out" "TOOLCHAIN${TAB}gradle/gradle-daemon-jvm.properties"
check "find-manifests: settings-gradle.lockfile is LOCK" has "$out" "LOCK${TAB}settings-gradle.lockfile"
check "find-manifests: version catalog is MANIFEST" has "$out" "MANIFEST${TAB}gradle/libs.versions.toml"

echo
[ "$fails" -eq 0 ] && { echo "all checks passed"; exit 0; }
echo "$fails check(s) failed"; exit 1
