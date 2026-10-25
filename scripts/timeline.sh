#!/usr/bin/env bash
# LifeLine: how every dependency changed across all saved snapshots - the long view
# a single diff cannot give ("maintained by A four years ago, by G today, and how it
# got there").
# Usage: timeline.sh <state-dir> public|private
#   public  -> LifeLine_Report/state/          (for timeline.md)
#   private -> LifeLine_Report/private/state/  (for private/timeline-sensitive.md)
# Every snapshot in the folder must carry "# visibility: <the one you name>"; a single
# file of the other kind stops the script before anything is printed, so a private
# snapshot dropped into state/ by mistake can never reach the public timeline.
# Output lines:
#   RUNS|count|first-date|last-date
#   TIMELINE|project|package|field|date=value|date=value|...
#       one line per field that took more than one value; each step is the run in
#       which the new value was first seen. Fields: version scope license install
#       latest deprecated archived maintainers publisher repo vulns local
#   PRESENCE|project|package|first-seen|last-seen|present|absent
#       only for packages that were not there in every run in which their project's
#       lock file was read; a run with a "# limit: <lock path> ..." line for that
#       project (node missing, unreadable lock) is not an absence
# "-" and "unknown" are gaps in the data, not values: they never start a new step.
set -u

DIR="${1:-}"
WANT="${2:-}"
[ -d "$DIR" ] && { [ "$WANT" = public ] || [ "$WANT" = private ]; } ||
  { echo "usage: timeline.sh <state-dir> public|private" >&2; exit 2; }
set -- "$DIR"/*.tsv
[ -f "$1" ] || { echo "RUNS|0|-|-"; exit 0; }
for f in "$@"; do
  v=$(sed -n 's/^# visibility: //p' "$f" | head -1)
  [ "$v" = "$WANT" ] || { echo "ERROR|$f is ${v:-unmarked}, expected $WANT - nothing printed" >&2; exit 2; }
done

# Run order: date, then same-day suffix (2026-10-24, 2026-10-24-2, 2026-10-24-10).
# A plain byte sort would put 2026-10-24-2.tsv before 2026-10-24.tsv ('-' < '.').
printf '%s\n' "$@" | awk '{ b = $0; sub(/^.*\//, "", b); sub(/\.tsv$/, "", b); n = split(b, f, "-")
  printf "%s\t%s\t%s\t%s\t%s\n", f[1], f[2], f[3], (n > 3 ? f[4] : 0), $0 }' |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3n -k4,4n | cut -f5 | tr '\n' '\0' | xargs -0 awk -F'\t' '
  # The project a "# limit:" line says was not read, or "" for a free note (same rule
  # as diff-state.sh: only "<lock path> not read|is lockfileVersion|not snapshotted ...
  # [project: <dir>]" lines count; free "# limit:" text and "# note:" lines do not).
  function limitproj(line,   lp, path, base, proj) {
    lp = substr(line, 10)
    if (!match(lp, / (not read|is lockfileVersion|not snapshotted)( |$)/)) return ""
    path = substr(lp, 1, RSTART - 1); base = path; sub(/^.*\//, "", base)
    if (base !~ /(\.lock|lockfile|-lock\.json|-lock\.yaml|\.lockb|\.lock\.json|go\.sum|\.resolved)$/) return ""
    proj = ""
    if (match(lp, /\[project: [^]]*\]$/)) proj = substr(lp, RSTART + 10, RLENGTH - 11)
    if (proj == "") { proj = path; if (proj ~ /\//) sub(/\/[^\/]*$/, "", proj); else proj = "." }
    return proj
  }
  function addset(cur, val,   n, a, i) {
    if (val == "-" || val == "unknown" || val == "") return cur
    if (cur == "") return val
    n = split(cur, a, ","); for (i = 1; i <= n; i++) if (a[i] == val) return cur
    return cur "," val
  }
  function rank(s) { return s == "direct-runtime" ? 5 : s == "vendored" ? 4 : s == "direct-dev" ? 3 : s == "transitive-runtime" ? 2 : s == "" ? 0 : 1 }
  function put(f, v) { if (v != "-" && v != "unknown" && v != "") val[run, k, f] = v }
  FNR == 1 { run++; date[run] = FILENAME; sub(/^.*\//, "", date[run]); sub(/\.tsv$/, "", date[run]) }
  # "# limit: <lock path> not read ..." - that project was not read in this run.
  /^# limit: / { if ((d = limitproj($0)) != "") blind[run, d] = 1; next }
  /^#/ || $1 == "project" { next }
  {
    k = $1 SUBSEP $3 SUBSEP ($5 == "vendored" ? "v" : "p"); keys[k] = 1; seen[run, k] = 1
    val[run, k, "version"] = addset(val[run, k, "version"], $4)
    if (rank($5) > rank(val[run, k, "scope"])) val[run, k, "scope"] = $5
    val[run, k, "license"] = addset(val[run, k, "license"], $6)
    if ($7 == "yes" || val[run, k, "install"] == "") put("install", $7)
    put("latest", $8); put("deprecated", $10); put("archived", $11); put("maintainers", $12)
    put("publisher", $13); put("repo", $14); put("vulns", $15); put("local", $16)
  }
  END {
    print "RUNS|" run "|" date[1] "|" date[run]
    nf = split("version scope license install latest deprecated archived maintainers publisher repo vulns local", F, " ")
    for (k in keys) {
      split(k, p, SUBSEP); name = p[2] (p[3] == "v" ? " (vendored)" : "")
      # Vendored rows come from VENDORED.md, not from a lock file: never blind.
      first = last = 0; present = 0; observed = 0
      for (r = 1; r <= run; r++) {
        if (p[3] != "v" && blind[r, p[1]]) continue
        observed++
        if (seen[r, k]) { if (!first) first = r; last = r; present++ }
      }
      if (present < observed) print "PRESENCE|" p[1] "|" name "|" date[first] "|" date[last] "|" present "|" observed - present
      for (i = 1; i <= nf; i++) {
        f = F[i]; line = ""; prev = ""; steps = 0
        for (r = 1; r <= run; r++) {
          if (!seen[r, k] || !((r, k, f) in val)) continue
          v = val[r, k, f]
          if (v != prev) { line = line "|" date[r] "=" v; prev = v; steps++ }
        }
        if (steps > 1) print "TIMELINE|" p[1] "|" name "|" f line
      }
    }
  }' | LC_ALL=C sort -t'|' -k1,1r -k2,2 -k3,3 -k4,4 |
  awk '/^RUNS\|/ { print; next } { rest[n++] = $0 } END { for (i = 0; i < n; i++) print rest[i] }'
