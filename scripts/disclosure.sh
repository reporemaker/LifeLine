#!/usr/bin/env bash
# LifeLine: responsible disclosure. From the PRIVATE snapshots, which known
# vulnerabilities were closed (may now be published) and which are still open (stay
# private, never published - not even as a count).
# Usage: disclosure.sh <private-state-dir>     (LifeLine_Report/private/state/)
# Output lines:
#   CLOSED|project|package|id|first-seen|closed-on|days-open
#       seen in an earlier run, gone in a later complete run, and not open anywhere
#       else today. This is the only line kind that may appear in a public file.
#   OPEN|project|package|id|first-seen|days-so-far           private report only
#   REOPENED|project|package|id|first-seen|closed-on|reopened-on   private report only
#       was gone, is back. The public "Closed vulnerabilities" table keeps its old
#       CLOSED row (cumulative); the public report never says it came back.
# Dates are YYYY-MM-DD (a same-day run suffix like -2 is dropped).
# An advisory id is reported as CLOSED only if, in the newest run, it is open in NO
# project: the same id open in one project and gone from another stays OPEN (one
# CLOSED line would give the open one away).
# A run says nothing - neither "seen" nor "gone" - about:
#   - every package, when it was offline or the OSV query failed;
#   - a project whose lock file could not be read (a "# limit:" line for it), or that
#     has no lock-file rows in that run (vendored rows alone do not count: a deleted
#     lock file must not read as "every package gone");
#   - a package whose vulns field is "-".
# So a missing lock, a missing node or a broken lock file can never turn an open
# vulnerability into a published "closed" one. Every snapshot must be private: a single
# public one stops the script before anything is printed.
set -u

DIR="${1:-}"
[ -d "$DIR" ] || { echo "usage: disclosure.sh <private-state-dir>" >&2; exit 2; }
set -- "$DIR"/*.tsv
[ -f "$1" ] || exit 0
for f in "$@"; do
  v=$(sed -n 's/^# visibility: //p' "$f" | head -1)
  [ "$v" = private ] || { echo "ERROR|$f is ${v:-unmarked}, expected private - nothing printed" >&2; exit 2; }
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
  function days(d,   y, m, dd) {
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m <= 2) { y--; m += 12 }
    return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + dd
  }
  FNR == 1 { run++; date[run] = FILENAME; sub(/^.*\//, "", date[run]); sub(/\.tsv$/, "", date[run]); day[run] = substr(date[run], 1, 10); partial[run] = 0 }
  /^# online: no/ { partial[run] = 1; next }
  # "# limit: <lock path> not read ..." blinds the project of that lock file; the OSV
  # failure line snapshot-state.sh writes blinds the whole run. A free note that merely
  # mentions OSV ("# note: OSV has no ecosystem for ...") blinds nothing.
  /^# limit: / {
    if ($0 ~ /^# limit: OSV batch query failed/) partial[run] = 1
    else if ((d = limitproj($0)) != "") blindproj[run, d] = 1
    next
  }
  /^#/ || $1 == "project" { next }
  {
    pk = $1 SUBSEP $3
    # Only lock-file rows prove that a project was read; vendored rows come from
    # VENDORED.md and are there even when the lock file is gone.
    if ($5 != "vendored") projseen[run, $1] = 1
    if ($15 == "-") { blind[run, pk] = 1; next }
    if ($15 == "none") next
    n = split($15, ids, ";")
    for (i = 1; i <= n; i++) {
      k = pk SUBSEP ids[i]; vk[k] = 1; hit[run, k] = 1
      openlast[ids[i]] = run          # newest run in which this id is open anywhere
    }
  }
  END {
    for (k in vk) {
      split(k, p, SUBSEP); pk = p[1] SUBSEP p[2]
      first = 0; closed = 0; reopened = 0; lastclosed = 0
      for (r = 1; r <= run; r++) {
        if (hit[r, k]) {
          if (!first) first = r
          if (closed) { reopened = r; lastclosed = closed; closed = 0 }
          continue
        }
        if (!first || closed || partial[r] || blindproj[r, p[1]] || blind[r, pk] || !projseen[r, p[1]]) continue
        # Gone in a complete run: checked without this id, or the package left a
        # project whose lock file was read.
        closed = r
      }
      if (closed && openlast[p[3]] == run) closed = 0   # open elsewhere today: not closed
      if (closed) print "CLOSED|" p[1] "|" p[2] "|" p[3] "|" day[first] "|" day[closed] "|" days(day[closed]) - days(day[first])
      else if (reopened) print "REOPENED|" p[1] "|" p[2] "|" p[3] "|" day[first] "|" day[lastclosed] "|" day[reopened]
      else print "OPEN|" p[1] "|" p[2] "|" p[3] "|" day[first] "|" days(day[run]) - days(day[first])
    }
  }' | LC_ALL=C sort -t'|' -k1,1 -k6,6 -k2,2 -k3,3 -k4,4
