#!/usr/bin/env bash
# LifeLine: a machine-readable snapshot of everything the project depends on today.
# One snapshot per run, saved by the skill as LifeLine_Report/state/<date>.tsv; comparing
# snapshots (diff-state.sh, timeline.sh) is how changes over months are tracked.
# Usage: snapshot-state.sh <project-root> [--deep]     full snapshot (PRIVATE: has vuln ids)
#        snapshot-state.sh --public <private.tsv>        the same snapshot made safe to publish
#   --deep: upstream health for transitive packages too (one request set per package -
#           slow on large trees). Default: direct dependencies and vendored entries.
#   --public: vulns column set to "-" (not collected), marked "# visibility: public".
#           The full snapshot goes to LifeLine_Report/private/state/, the public one to
#           LifeLine_Report/state/. Open vulnerabilities never leave private/.
# Output (stdout, TSV): "#" meta lines, one header line, then one row per package:
#   project ecosystem package version scope license install latest published
#   deprecated archived maintainers publisher repo vulns local
# scope: direct-runtime | direct-dev | transitive-runtime | transitive-dev | vendored
# "-" = not collected this run (offline, not in scope, unsupported) - never a change.
# "unknown" = asked, no answer. vulns: OSV ids ";"-joined, or "none".
# Supported: npm lock files (needs node to read them), Gradle lock files
# (gradle.lockfile, *-gradle.lockfile; plain awk), VENDORED.md.
# Two kinds of "#" lines tell the report what this snapshot could not see:
#   "# limit: <lock path> not read|not snapshotted ... [project: <dir>]"
#       that project's packages are unknown in this run (diff-state, timeline and
#       disclosure treat it as not read, never as "everything removed");
#   "# limit: OSV batch query failed - vulns not collected"   the whole run's vulns;
#   "# note: <free text>"   anything else worth repeating in the report's Limits.
# Write free text as "# note:", never as "# limit:". The report repeats both kinds.
# LIFELINE_OFFLINE=1 skips every network call (tests, air-gapped machines).
set -u

if [ "${1:-}" = "--public" ]; then
  [ -f "${2:-}" ] || { echo "usage: snapshot-state.sh --public <private.tsv>" >&2; exit 2; }
  grep -q '^# visibility: private$' "$2" || { echo "ERROR|$2 is not a private snapshot" >&2; exit 1; }
  awk -F'\t' -v OFS='\t' '
    /^# visibility: / { print "# visibility: public"; next }
    /^#/ || $1 == "project" { print; next }
    { $15 = "-"; print }' "$2"
  exit 0
fi

ROOT="${1:-}"
DEEP=0
[ "${2:-}" = "--deep" ] && DEEP=1
[ -n "$ROOT" ] || { echo "usage: snapshot-state.sh <project-root> [--deep]" >&2; exit 2; }
SELF=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT" 2>/dev/null || { echo "ERROR|cannot access $ROOT" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/lifeline-state.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT
TAB=$(printf '\t')

NET=1
if [ "${LIFELINE_OFFLINE:-0}" = 1 ]; then NET=0
elif ! command -v curl >/dev/null 2>&1 || ! curl -s --max-time 6 -o /dev/null "https://api.osv.dev" 2>/dev/null; then NET=0; fi

# Gradle: the build root of a lock file is the nearest directory up with a settings
# script; every module's lock file belongs to that one project (app/gradle.lockfile -> ".").
gradle_root() {
  d=$1
  while :; do
    { [ -f "$d/settings.gradle" ] || [ -f "$d/settings.gradle.kts" ]; } && { echo "$d"; return; }
    [ "$d" = . ] && break
    d=$(dirname "$d")
  done
  echo "$1"
}

# All Gradle lock files of one build root -> package rows. Scope from the configuration
# names: a release runtime classpath (or plain runtimeClasspath) ships to users, every
# other configuration (debug, test, lint, compiler, plugin classpaths) is dev. Direct =
# named in a build script, as a version-catalog accessor (libs.foo.bar, bundles too) or
# a literal "group:name[:version]" string. Packages added by plugins (kotlin-stdlib, AGP's
# viewbinding) are not named anywhere, so they are transitive.
gradle_rows() {
  root=$1
  find "$root" \( -name build -o -name .gradle -o -name .git -o -name node_modules \) -prune -o \
    -type f \( -name gradle.lockfile -o -name '*-gradle.lockfile' \) -print 2>/dev/null > "$TMP/g.locks"
  find "$root" \( -name build -o -name .gradle -o -name .git -o -name node_modules \) -prune -o \
    -type f \( -name build.gradle -o -name build.gradle.kts \) -print 2>/dev/null > "$TMP/g.builds"
  : > "$TMP/g.cats"; [ -d "$root/gradle" ] && find "$root/gradle" -maxdepth 1 -type f -name '*.versions.toml' > "$TMP/g.cats"
  : > "$TMP/g.catalog"
  [ -s "$TMP/g.cats" ] && tr '\n' '\0' < "$TMP/g.cats" | xargs -0 awk '
    function norm(a) { a = tolower(a); gsub(/[-_.]/, ".", a); return a }
    function q(s, key,   m) {   # value of key = "..." in an inline table, or ""
      if (!match(s, key "[ \t]*=[ \t]*\"[^\"]*\"")) return ""
      m = substr(s, RSTART, RLENGTH); sub(/^[^"]*"/, "", m); sub(/"$/, "", m); return m
    }
    FNR == 1 { cat = FILENAME; sub(/^.*\//, "", cat); sub(/\.versions\.toml$/, "", cat); sec = ""; inb = 0 }
    /^[ \t]*#/ { next }
    /^[ \t]*\[[A-Za-z]+\][ \t]*$/ { sec = $0; gsub(/[][ \t]/, "", sec); inb = 0; next }
    sec == "libraries" && /=/ {
      alias = $0; sub(/[ \t]*=.*/, "", alias); gsub(/[ \t"]/, "", alias)
      rest = $0; sub(/^[^=]*=[ \t]*/, "", rest); ga = ""
      if ((m = q(rest, "module")) != "") ga = m
      else if ((g = q(rest, "group")) != "" && (n = q(rest, "name")) != "") ga = g ":" n
      else if (rest ~ /^"[^"]*"/) { m = rest; sub(/^"/, "", m); sub(/".*$/, "", m); split(m, p, ":"); if (p[2] != "") ga = p[1] ":" p[2] }
      if (ga != "") print "LIB\t" cat "\t" norm(alias) "\t" ga
      next
    }
    sec == "bundles" {
      line = $0
      if (!inb) { if (line !~ /=/) next; b = line; sub(/[ \t]*=.*/, "", b); gsub(/[ \t"]/, "", b); sub(/^[^=]*=/, "", line); inb = 1 }
      while (match(line, /"[^"]*"/)) { print "BUN\t" cat "\t" norm(b) "\t" norm(substr(line, RSTART + 1, RLENGTH - 2)); line = substr(line, RSTART + RLENGTH) }
      if ($0 ~ /\]/) inb = 0
    }' > "$TMP/g.catalog"
  : > "$TMP/g.direct"
  if [ -s "$TMP/g.builds" ]; then
    # Catalog accessors used in build scripts, and literal coordinates.
    tr '\n' '\0' < "$TMP/g.builds" | xargs -0 grep -ohE '[A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9_.]*[A-Za-z0-9_]' 2>/dev/null |
      awk -F'\t' '
        function norm(a) { a = tolower(a); gsub(/[-_.]/, ".", a); return a }
        FILENAME == ARGV[1] { if ($1 == "LIB") lib[$2 SUBSEP $3] = $4; else bun[$2 SUBSEP $3] = bun[$2 SUBSEP $3] " " $4; cats[$2] = 1; next }
        {
          c = $0; sub(/\..*/, "", c); if (!(c in cats)) next
          r = substr($0, length(c) + 2); sub(/\.(get|asProvider)$/, "", r)
          if (r ~ /^(plugins|versions)\./) next
          if (r ~ /^bundles\./) { n = split(bun[c SUBSEP norm(substr(r, 9))], a, " "); for (i = 1; i <= n; i++) if ((c SUBSEP a[i]) in lib) print lib[c SUBSEP a[i]]; next }
          if ((c SUBSEP norm(r)) in lib) print lib[c SUBSEP norm(r)]
        }' "$TMP/g.catalog" - >> "$TMP/g.direct"
    tr '\n' '\0' < "$TMP/g.builds" | xargs -0 grep -ohE "[\"'][A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+(:[^\"'\$]*)?[\"']" 2>/dev/null |
      sed -E "s/^[\"']//; s/[\"']$//" | awk -F: '{ print $1 ":" $2 }' >> "$TMP/g.direct"
  fi
  [ -s "$TMP/g.locks" ] || return 0
  tr '\n' '\0' < "$TMP/g.locks" | xargs -0 awk -v proj="$root" -v direct="$TMP/g.direct" '
    function rank(s) { return s == "direct-runtime" ? 4 : s == "direct-dev" ? 3 : s == "transitive-runtime" ? 2 : 1 }
    BEGIN { while ((getline l < direct) > 0) d[l] = 1 }
    /^#/ || /^empty=/ || index($0, "=") == 0 { next }
    {
      coord = substr($0, 1, index($0, "=") - 1); confs = substr($0, index($0, "=") + 1)
      if (split(coord, c, ":") < 3) next
      ga = c[1] ":" c[2]; rt = 0; n = split(confs, cf, ",")
      for (i = 1; i <= n; i++) if (cf[i] == "runtimeClasspath" || (cf[i] ~ /[Rr]eleaseRuntimeClasspath$/ && cf[i] !~ /Test/)) rt = 1
      s = (ga in d) ? (rt ? "direct-runtime" : "direct-dev") : (rt ? "transitive-runtime" : "transitive-dev")
      k = ga SUBSEP c[3]; if (!(k in sc) || rank(s) > rank(sc[k])) sc[k] = s
    }
    END { for (k in sc) { split(k, p, SUBSEP); print proj "\tMaven\t" p[1] "\t" p[2] "\t" sc[k] "\t-\t-" } }'
}

echo "# LifeLine state v1"
echo "# visibility: private"
echo "# generated: $(date +%F)"
echo "# project: $(basename "$(pwd -P)")"
echo "# deep: $([ $DEEP -eq 1 ] && echo yes || echo no)"
echo "# online: $([ $NET -eq 1 ] && echo yes || echo no)"

# --- 1. Package rows from lock files: project eco package version scope license install ---
: > "$TMP/rows"
bash "$SELF/find-manifests.sh" . | while IFS="$TAB" read -r cat path; do
  [ "$cat" = LOCK ] || continue
  proj=$(dirname "$path")
  case "$path" in
    package-lock.json|*/package-lock.json)
      if ! command -v node >/dev/null 2>&1; then
        echo "# limit: $path not read (node missing)"; continue
      fi
      node -e '
        const fs = require("fs"); const [lock, proj] = process.argv.slice(1);
        const l = JSON.parse(fs.readFileSync(lock, "utf8"));
        if (!l.packages) { console.log("LIMIT\t" + lock + " is lockfileVersion 1 (no packages map)"); process.exit(0) }
        const root = l.packages[""] || {};
        const run = new Set([...Object.keys(root.dependencies || {}), ...Object.keys(root.optionalDependencies || {})]);
        const dev = new Set(Object.keys(root.devDependencies || {}));
        const seen = new Set();
        for (const [k, v] of Object.entries(l.packages)) {
          if (!k.includes("node_modules/") || v.link) continue;
          const name = v.name || k.slice(k.lastIndexOf("node_modules/") + 13);
          const top = k === "node_modules/" + name;
          const scope = top && run.has(name) ? "direct-runtime" : top && dev.has(name) ? "direct-dev"
            : (v.dev || v.devOptional) ? "transitive-dev" : "transitive-runtime";
          const lic = typeof v.license === "string" ? v.license : (v.license && v.license.type) || "unknown";
          const row = [proj, "npm", name, v.version || "unknown", scope, lic.replace(/\s+/g, " "), v.hasInstallScript ? "yes" : "no"].join("\t");
          if (!seen.has(row)) { seen.add(row); console.log(row) }
        }' "$path" "$proj" > "$TMP/lock.out" 2>/dev/null
      if [ $? -ne 0 ]; then
        # Unreadable lock (broken JSON, unexpected shape): say so, add no rows from it.
        echo "# limit: $path not read (lock file could not be parsed)"; continue
      fi
      while IFS= read -r line; do
        case "$line" in LIMIT"$TAB"*) echo "# limit: ${line#LIMIT$TAB}" ;; *) echo "$line" >> "$TMP/rows" ;; esac
      done < "$TMP/lock.out"
      ;;
    gradle.lockfile|*/gradle.lockfile|*-gradle.lockfile)
      groot=$(gradle_root "$proj")
      # One pass per build root covers all of its lock files.
      grep -qxF "$groot" "$TMP/gradle.done" 2>/dev/null && continue
      echo "$groot" >> "$TMP/gradle.done"
      if gradle_rows "$groot" > "$TMP/gradle.out" 2>/dev/null; then
        cat "$TMP/gradle.out" >> "$TMP/rows"
        echo "# note: $groot: Gradle lock files read; runtime = release runtime classpaths, other configurations dev; licences are not in Gradle locks (direct ones come from deps.dev)"
      else
        echo "# limit: $path not read (lock file could not be parsed) [project: $groot]"
      fi
      ;;
    *) echo "# limit: $path not snapshotted (format not supported yet)" ;;
  esac
done

# Vendored entries (project ".", scope vendored); latest + local from check-vendored.sh.
: > "$TMP/vend"
if [ -f VENDORED.md ]; then
  awk '
    function flush() { if (name != "") print name "\t" (eco ? eco : "none") "\t" (pkg ? pkg : "none") "\t" (ver ? ver : "unknown") "\t" (lic ? lic : "unknown") }
    /^## / { flush(); name = substr($0, 4); eco = pkg = ver = lic = "" }
    /^- Ecosystem:/    { sub(/^- Ecosystem:[ \t]*/, "");    eco = $0 }
    /^- Package-Name:/ { sub(/^- Package-Name:[ \t]*/, ""); pkg = $0 }
    /^- Version:/      { sub(/^- Version:[ \t]*/, "");      ver = $0 }
    /^- License:/      { sub(/^- License:[ \t]*/, "");      lic = $0 }
    END { flush() }' VENDORED.md > "$TMP/ledger"
  bash "$SELF/check-vendored.sh" . | grep '^ENTRY|' > "$TMP/entries"
  while IFS="$TAB" read -r name eco pkg ver lic; do
    e=$(awk -F'|' -v n="$name" '$2 == n' "$TMP/entries" | head -1)
    latest=$(printf '%s' "$e" | cut -d'|' -f4); local_state=$(printf '%s' "$e" | cut -d'|' -f7)
    # Offline the upstream version was not asked for ("-"), not asked and unanswered ("unknown").
    [ "$NET" -eq 1 ] || latest="-"
    shown=$pkg; [ "$pkg" = none ] && shown=$name
    # Row key for the join: the ledger entry name (unique), carried in the package
    # column as "shown" plus the entry name when they differ.
    printf '.\t%s\t%s\t%s\tvendored\t%s\t-\n' "$eco" "$shown" "$ver" "$lic" >> "$TMP/rows"
    printf '%s\t%s\t%s\t%s\n' "$shown" "$ver" "${latest:--}" "${local_state:--}" >> "$TMP/vend"
  done < "$TMP/ledger"
fi

# --- 2. Upstream health per unique ecosystem|package in scope ---
: > "$TMP/health"
if [ "$NET" -eq 1 ]; then
  awk -F'\t' -v deep="$DEEP" '$2 != "none" && (deep == 1 || $5 ~ /^direct-/ || $5 == "vendored") { print $2 "\t" $3 }' "$TMP/rows" |
    LC_ALL=C sort -u | while IFS="$TAB" read -r eco pkg; do
      bash "$SELF/upstream-health.sh" "$eco" "$pkg" | grep '^HEALTH|' |
        awk -F'|' -v OFS='\t' '{ gsub(/\t/, " "); print $2, $3, $4, $5, $7, $10, $13, $14, $9, $12 }' >> "$TMP/health"
    done
fi

# --- 3. Known vulnerabilities: OSV batch queries, 1000 rows each (the API limit) ---
# Only ecosystems OSV knows go into the batch: one unknown name ("github" for a vendored
# repo) fails the whole request. The rest keep vulns "-" and get a note.
OSVECO=" npm PyPI Maven Go crates.io NuGet RubyGems Packagist Pub Hex "
awk -F'\t' -v k="$OSVECO" '$2 != "none" && $4 != "unknown" && index(k, " " $2 " ") { print NR "\t" $2 "\t" $3 "\t" $4 }' "$TMP/rows" > "$TMP/q"
awk -F'\t' -v k="$OSVECO" '$2 != "none" && !index(k, " " $2 " ") { n[$2]++ } END { for (e in n) print "# note: OSV has no ecosystem for " e " rows (" n[e] ") - their vulns are not collected" }' "$TMP/rows"
: > "$TMP/vulns"
if [ "$NET" -eq 1 ] && [ -s "$TMP/q" ]; then
  split -l 1000 "$TMP/q" "$TMP/qpart."
  : > "$TMP/ids"; fail=0
  for part in "$TMP"/qpart.*; do
    # OSV ecosystem names are case-sensitive: npm, PyPI, crates.io, Go, Maven, NuGet ...
    {
      printf '{"queries":['
      awk -F'\t' '{ gsub(/\\/, "\\\\", $3); gsub(/"/, "\\\"", $3); gsub(/"/, "\\\"", $4)
                    printf "%s{\"package\":{\"name\":\"%s\",\"ecosystem\":\"%s\"},\"version\":\"%s\"}", (NR > 1 ? "," : ""), $3, $2, $4 }' "$part"
      printf ']}'
    } > "$TMP/body"
    curl -s --max-time 60 -X POST "https://api.osv.dev/v1/querybatch" -H 'Content-Type: application/json' \
      --data-binary @"$TMP/body" > "$TMP/osv" 2>/dev/null || : > "$TMP/osv"
    grep -q '"results"' "$TMP/osv" || { fail=1; break; }
    # A paginated answer would hide the ids past the first page; treat it as a failure.
    grep -q '"next_page_token"' "$TMP/osv" && { fail=1; break; }
    # Split "results":[ {...}, {...} ] into one line of ids per query, in order.
    awk 'BEGIN { RS = "\001" } {
      i = index($0, "\"results\":["); if (!i) exit
      s = substr($0, i + 11); depth = 0; elem = ""
      for (p = 1; p <= length(s); p++) {
        c = substr(s, p, 1)
        if (c == "{") depth++
        if (depth > 0) elem = elem c
        if (c == "}") { depth--; if (depth == 0) {
            ids = ""; t = elem
            while (match(t, /"id":"[^"]*"/)) { id = substr(t, RSTART + 6, RLENGTH - 7); ids = ids (ids ? ";" : "") id; t = substr(t, RSTART + RLENGTH) }
            print (ids ? ids : "none"); elem = "" } }
        if (c == "]" && depth == 0) break
      } }' "$TMP/osv" > "$TMP/ids.part"
    # One answer per query, or the whole run is treated as not collected.
    [ "$(wc -l < "$TMP/ids.part")" -eq "$(wc -l < "$part")" ] || { fail=1; break; }
    cat "$TMP/ids.part" >> "$TMP/ids"
  done
  if [ "$fail" -eq 0 ]; then
    paste "$TMP/q" "$TMP/ids" | awk -F'\t' -v OFS='\t' '{ print $1, $5 }' > "$TMP/vulns"
  else
    # All or nothing: a partial list would make the missing ones look fixed.
    echo "# limit: OSV batch query failed - vulns not collected"
  fi
fi

# --- 4. Join and print ---
printf 'project\tecosystem\tpackage\tversion\tscope\tlicense\tinstall\tlatest\tpublished\tdeprecated\tarchived\tmaintainers\tpublisher\trepo\tvulns\tlocal\n'
awk -F'\t' -v OFS='\t' '
  FILENAME == ARGV[1] { h[$1 "|" $2] = $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 "\t" $9
                        if ($10 != "" && $10 != "unknown") hl[$1 "|" $2] = $10; next }
  FILENAME == ARGV[2] { v[$1] = $2; next }
  FILENAME == ARGV[3] { vl[$1 "|" $2] = $3; vs[$1 "|" $2] = $4; next }
  {
    hv = (($2 "|" $3) in h) ? h[$2 "|" $3] : "-\t-\t-\t-\t-\t-\t-"
    vk = $3 "|" $4   # vendored rows: package + recorded version (two entries of one package differ by version)
    if ($5 == "vendored" && (vk in vl)) { split(hv, a, "\t"); if (a[1] == "-") a[1] = vl[vk]; hv = a[1] "\t" a[2] "\t" a[3] "\t" a[4] "\t" a[5] "\t" a[6] "\t" a[7] }
    # Lock files without licences (Gradle): take the registry licence for direct rows.
    if ($6 == "-" && (($2 "|" $3) in hl)) $6 = hl[$2 "|" $3]
    vv = (FNR in v) ? v[FNR] : "-"
    lo = ($5 == "vendored" && (vk in vs)) ? vs[vk] : "-"
    print $0, hv, vv, lo
  }' "$TMP/health" "$TMP/vulns" "$TMP/vend" "$TMP/rows" | LC_ALL=C sort -t "$TAB" -k1,1 -k3,3 -k4,4
