#!/usr/bin/env bash
# LifeLine: how every dependency changed across all saved snapshots - the long view
# a single diff cannot give ("maintained by A four years ago, by G today, and how it
# got there").
# Usage: timeline.sh <state-dir>        (LifeLine_Report/state/, files *.tsv in date order)
# Output lines:
#   RUNS|count|first-date|last-date
#   TIMELINE|project|package|field|date=value|date=value|...
#       one line per field that took more than one value; each step is the run in
#       which the new value was first seen. Fields: version scope license install
#       latest deprecated archived maintainers publisher repo vulns local
#   PRESENCE|project|package|first-seen|last-seen|present|absent
#       only for packages that were not there in every run
# "-" and "unknown" are gaps in the data, not values: they never start a new step.
set -u

DIR="${1:-}"
[ -d "$DIR" ] || { echo "usage: timeline.sh <state-dir>" >&2; exit 2; }
set -- "$DIR"/*.tsv
[ -f "$1" ] || { echo "RUNS|0|-|-"; exit 0; }

# Run order: date, then same-day suffix (2026-10-24, 2026-10-24-2, 2026-10-24-10).
# A plain byte sort would put 2026-10-24-2.tsv before 2026-10-24.tsv ('-' < '.').
printf '%s\n' "$@" | awk '{ b = $0; sub(/^.*\//, "", b); sub(/\.tsv$/, "", b); n = split(b, f, "-")
  printf "%s\t%s\t%s\t%s\t%s\n", f[1], f[2], f[3], (n > 3 ? f[4] : 0), $0 }' |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3n -k4,4n | cut -f5 | tr '\n' '\0' | xargs -0 awk -F'\t' '
  function addset(cur, val,   n, a, i) {
    if (val == "-" || val == "unknown" || val == "") return cur
    if (cur == "") return val
    n = split(cur, a, ","); for (i = 1; i <= n; i++) if (a[i] == val) return cur
    return cur "," val
  }
  function rank(s) { return s == "direct-runtime" ? 5 : s == "vendored" ? 4 : s == "direct-dev" ? 3 : s == "transitive-runtime" ? 2 : s == "" ? 0 : 1 }
  function put(f, v) { if (v != "-" && v != "unknown" && v != "") val[run, k, f] = v }
  FNR == 1 { run++; date[run] = FILENAME; sub(/^.*\//, "", date[run]); sub(/\.tsv$/, "", date[run]) }
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
      first = last = 0; present = 0
      for (r = 1; r <= run; r++) if (seen[r, k]) { if (!first) first = r; last = r; present++ }
      if (present < run) print "PRESENCE|" p[1] "|" name "|" date[first] "|" date[last] "|" present "|" run - present
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
