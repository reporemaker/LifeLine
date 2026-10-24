#!/usr/bin/env bash
# LifeLine: responsible disclosure. From the PRIVATE snapshots, which known
# vulnerabilities were closed (may now be published) and which are still open (stay
# private, never published - not even as a count).
# Usage: disclosure.sh <private-state-dir>     (LifeLine_Report/private/state/)
# Output lines:
#   CLOSED|project|package|id|first-seen|closed-on|days-open
#       seen in an earlier run, gone in a later one (fixed, upgraded or the package removed)
#   OPEN|project|package|id|first-seen|days-so-far       private report only
# A run that could not query OSV (offline, or the package row has vulns "-") says
# nothing about that package: it is neither "seen" nor "gone" in that run.
set -u

DIR="${1:-}"
[ -d "$DIR" ] || { echo "usage: disclosure.sh <private-state-dir>" >&2; exit 2; }
set -- "$DIR"/*.tsv
[ -f "$1" ] || exit 0

# Run order: date, then same-day suffix (2026-10-24, 2026-10-24-2, 2026-10-24-10).
# A plain byte sort would put 2026-10-24-2.tsv before 2026-10-24.tsv ('-' < '.').
printf '%s\n' "$@" | awk '{ b = $0; sub(/^.*\//, "", b); sub(/\.tsv$/, "", b); n = split(b, f, "-")
  printf "%s\t%s\t%s\t%s\t%s\n", f[1], f[2], f[3], (n > 3 ? f[4] : 0), $0 }' |
  LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3n -k4,4n | cut -f5 | tr '\n' '\0' | xargs -0 awk -F'\t' '
  function days(d,   y, m, dd) {
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m <= 2) { y--; m += 12 }
    return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + dd
  }
  FNR == 1 { run++; date[run] = FILENAME; sub(/^.*\//, "", date[run]); sub(/\.tsv$/, "", date[run]); online[run] = 1 }
  /^# online: no/ { online[run] = 0; next }
  /^# visibility: public/ { print "ERROR|" FILENAME " is a public snapshot - pass the private state dir" > "/dev/stderr"; exit 2 }
  /^#/ || $1 == "project" { next }
  {
    pk = $1 SUBSEP $3
    if (!online[run] || $15 == "-") { blind[run, pk] = 1; next }
    checked[run, pk] = 1; pkgs[pk] = 1
    if ($15 == "none") next
    n = split($15, ids, ";")
    for (i = 1; i <= n; i++) { k = pk SUBSEP ids[i]; vk[k] = 1; hit[run, k] = 1 }
  }
  END {
    for (k in vk) {
      split(k, p, SUBSEP); pk = p[1] SUBSEP p[2]
      first = 0; lastseen = 0; closed = 0
      for (r = 1; r <= run; r++) {
        if (hit[r, k]) { if (!first) first = r; lastseen = r; closed = 0; continue }
        if (!first || closed) continue
        # Gone: the package was checked without this id, or the package left the tree
        # while OSV was reachable in that run.
        if (checked[r, pk] || (online[r] && !blind[r, pk])) closed = r
      }
      if (closed) print "CLOSED|" p[1] "|" p[2] "|" p[3] "|" date[first] "|" date[closed] "|" days(date[closed]) - days(date[first])
      else print "OPEN|" p[1] "|" p[2] "|" p[3] "|" date[first] "|" days(date[run]) - days(date[first])
    }
  }' | LC_ALL=C sort -t'|' -k1,1 -k6,6 -k2,2 -k3,3 -k4,4
