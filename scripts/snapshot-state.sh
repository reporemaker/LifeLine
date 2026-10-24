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
# Supported: npm lock files (needs node to read them), VENDORED.md. Everything else is
# listed as a "# limit:" line - the report must repeat it.
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
if ! command -v curl >/dev/null 2>&1 || ! curl -s --max-time 6 -o /dev/null "https://api.osv.dev" 2>/dev/null; then NET=0; fi

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
        awk -F'|' -v OFS='\t' '{ gsub(/\t/, " "); print $2, $3, $4, $5, $7, $10, $13, $14, $9 }' >> "$TMP/health"
    done
fi

# --- 3. Known vulnerabilities: OSV batch queries, 1000 rows each (the API limit) ---
awk -F'\t' '$2 != "none" && $4 != "unknown" { print NR "\t" $2 "\t" $3 "\t" $4 }' "$TMP/rows" > "$TMP/q"
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
  FILENAME == ARGV[1] { h[$1 "|" $2] = $3 "\t" $4 "\t" $5 "\t" $6 "\t" $7 "\t" $8 "\t" $9; next }
  FILENAME == ARGV[2] { v[$1] = $2; next }
  FILENAME == ARGV[3] { vl[$1 "|" $2] = $3; vs[$1 "|" $2] = $4; next }
  {
    hv = (($2 "|" $3) in h) ? h[$2 "|" $3] : "-\t-\t-\t-\t-\t-\t-"
    vk = $3 "|" $4   # vendored rows: package + recorded version (two entries of one package differ by version)
    if ($5 == "vendored" && (vk in vl)) { split(hv, a, "\t"); if (a[1] == "-") a[1] = vl[vk]; hv = a[1] "\t" a[2] "\t" a[3] "\t" a[4] "\t" a[5] "\t" a[6] "\t" a[7] }
    vv = (FNR in v) ? v[FNR] : "-"
    lo = ($5 == "vendored" && (vk in vs)) ? vs[vk] : "-"
    print $0, hv, vv, lo
  }' "$TMP/health" "$TMP/vulns" "$TMP/vend" "$TMP/rows" | LC_ALL=C sort -t "$TAB" -k1,1 -k3,3 -k4,4
