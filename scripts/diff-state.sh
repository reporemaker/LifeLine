#!/usr/bin/env bash
# LifeLine: what changed between two state snapshots (snapshot-state.sh output)?
# Usage: diff-state.sh <old.tsv> <new.tsv>
# Output lines:
#   CHANGE|severity|project|package|field|old|new|note
#     severity: high | medium | info   (report: 🔴 / 🟡 / ⚪)
#   SUMMARY|added|removed|changed|high|medium
# A field that is "-" or "unknown" on either side was not collected and is never a change.
# Rows of one package in one project (several installed versions) are merged first.
# Compare like with like: two public snapshots (for public reports) or two private ones
# (for the private change report). Mixing them is refused.
set -u

OLD="${1:-}"; NEW="${2:-}"
[ -f "$OLD" ] && [ -f "$NEW" ] || { echo "usage: diff-state.sh <old.tsv> <new.tsv>" >&2; exit 2; }
vis() { sed -n 's/^# visibility: //p' "$1" | head -1; }
for f in "$OLD" "$NEW"; do
  case "$(vis "$f")" in public|private) ;; *) echo "ERROR|$f has no '# visibility:' line - not a snapshot" >&2; exit 2 ;; esac
done
[ "$(vis "$OLD")" = "$(vis "$NEW")" ] || { echo "ERROR|one snapshot is public, the other private - compare like with like" >&2; exit 2; }

awk -F'\t' '
  # The project a "# limit:" line says was not read, or "" for a free note. Only the
  # lines snapshot-state.sh writes about a lock file count: "<lock path> not read ...",
  # "<lock path> is lockfileVersion 1 ...", "<lock path> not snapshotted ...", optionally
  # ending in "[project: <dir>]". Any other "# limit:" text, and every "# note:" line,
  # is a note for the report and blinds nothing.
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
  # Days since 0000-03-01 for a YYYY-MM-DD date (portable: no mktime in BSD awk).
  function days(d,   y, m, dd) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return -1
    y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
    if (m <= 2) { y--; m += 12 }
    return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + dd
  }
  function rank(s) { return s == "direct-runtime" ? 5 : s == "vendored" ? 4 : s == "direct-dev" ? 3 : s == "transitive-runtime" ? 2 : 1 }
  function addset(cur, val,   n, a, i) {
    if (val == "-" || val == "unknown" || val == "") return cur
    if (cur == "" || cur == "-") return val
    n = split(cur, a, ","); for (i = 1; i <= n; i++) if (a[i] == val) return cur
    return cur "," val
  }
  function idset(cur, val,   n, a, i, out) {   # union of ";"-lists
    if (val == "-" ) return cur
    if (cur == "" || cur == "-" || cur == "none") cur = ""
    if (val == "none") return cur == "" ? "none" : cur
    n = split(val, a, ";"); out = cur
    for (i = 1; i <= n; i++) if (index(";" out ";", ";" a[i] ";") == 0) out = out (out == "" ? "" : ";") a[i]
    return out
  }
  function keep(cur, val) { return (val != "-" && val != "unknown" && val != "") ? val : (cur == "" ? "-" : cur) }
  function load(side,   k) {
    k = $1 SUBSEP $3 SUBSEP ($5 == "vendored" ? "v" : "p")
    keys[k] = 1; seen[side, k] = 1
    ver[side, k] = addset(ver[side, k], $4)
    if (sc[side, k] == "" || rank($5) > rank(sc[side, k])) sc[side, k] = $5
    lic[side, k] = addset(lic[side, k], $6)
    if ($7 == "yes") ins[side, k] = "yes"; else if (ins[side, k] == "" && $7 == "no") ins[side, k] = "no"
    lat[side, k] = keep(lat[side, k], $8);  pub[side, k] = keep(pub[side, k], $9)
    dep[side, k] = keep(dep[side, k], $10); arc[side, k] = keep(arc[side, k], $11)
    mnt[side, k] = keep(mnt[side, k], $12); pbl[side, k] = keep(pbl[side, k], $13)
    rep[side, k] = keep(rep[side, k], $14); vul[side, k] = idset(vul[side, k], $15)
    loc[side, k] = keep(loc[side, k], $16)
  }
  function known(v) { return v != "" && v != "-" && v != "unknown" }
  function out(sev, k, field, o, n, note,   p) {
    split(k, p, SUBSEP)
    print "CHANGE|" sev "|" p[1] "|" p[2] (p[3] == "v" ? " (vendored)" : "") "|" field "|" o "|" n "|" note
    changed[k] = 1; if (sev == "high") hi++; if (sev == "medium") me++
  }
  function inlist(name, list) { return index(";" list ";", ";" name ";") > 0 }
  # A ";" list minus another ";" list.
  function minus(a, b,   n, x, i, r) { n = split(a, x, ";"); r = ""; for (i = 1; i <= n; i++) if (!inlist(x[i], b)) r = r (r == "" ? "" : ";") x[i]; return r }

  FNR == 1 { side = (++file == 1) ? "o" : "n" }   # by position: the same path may be passed twice
  /^#/ {
    if ($0 ~ /^# generated: /) gen[side] = substr($0, 14)
    # "# limit: <lock path> not read ..." - that project was not read in this snapshot.
    if ($0 ~ /^# limit: / && (d = limitproj($0)) != "") blind[side, d] = 1
    next
  }
  $1 == "project" { next }
  { load(side) }

  END {
    today = days(gen["n"])
    for (k in keys) {
      if (!seen["o", k]) {
        split(k, pp, SUBSEP)
        if (blind["o", pp[1]]) continue   # lock not read last time: unknown, not added
        s = sc["n", k]
        sev = (s == "direct-runtime" || s == "transitive-runtime" || s == "vendored") ? "medium" : "info"
        note = (s == "transitive-runtime") ? "new package in the runtime tree - check who pulls it in and why" : ""
        if (ins["n", k] == "yes") { sev = "high"; note = "new package that runs an install script" }
        out(sev, k, "added", "-", ver["n", k] " " s, note); add++; continue
      }
      if (!seen["n", k]) {
        split(k, pp, SUBSEP)
        if (blind["n", pp[1]]) continue   # lock not read this time: unknown, not removed
        out("info", k, "removed", ver["o", k] " " sc["o", k], "-", ""); rem++; continue
      }

      if (ver["o", k] != ver["n", k] && known(ver["o", k]) && known(ver["n", k])) out("info", k, "version", ver["o", k], ver["n", k], "")
      if (sc["o", k] != sc["n", k]) {
        sev = (sc["n", k] ~ /runtime/ && sc["o", k] ~ /dev/) ? "medium" : "info"
        out(sev, k, "scope", sc["o", k], sc["n", k], sev == "medium" ? "now ships to users" : "")
      }
      if (known(lic["o", k]) && known(lic["n", k]) && lic["o", k] != lic["n", k])
        out(lic["n", k] ~ /GPL|SSPL|EUPL/ ? "high" : "medium", k, "license", lic["o", k], lic["n", k], lic["n", k] ~ /GPL|SSPL|EUPL/ ? "copyleft now" : "")
      if (ins["o", k] == "no" && ins["n", k] == "yes") out("high", k, "install", "no", "yes", "now runs code at install time")
      if (known(lat["o", k]) && known(lat["n", k]) && lat["o", k] != lat["n", k]) out("info", k, "latest", lat["o", k], lat["n", k], "new upstream release")
      if (dep["o", k] == "no" && dep["n", k] ~ /^yes/) out("medium", k, "deprecated", "no", dep["n", k], "")
      if (arc["o", k] == "no" && arc["n", k] == "yes") out("medium", k, "archived", "no", "yes", "upstream stopped")
      if (arc["o", k] == "yes" && arc["n", k] == "no") out("info", k, "archived", "yes", "no", "upstream revived")
      if (known(mnt["o", k]) && known(mnt["n", k]) && mnt["o", k] != mnt["n", k]) {
        gone = minus(mnt["o", k], mnt["n", k]); came = minus(mnt["n", k], mnt["o", k])
        if (gone != "" && came != "") out("high", k, "maintainers", mnt["o", k], mnt["n", k], "handover: left " gone ", joined " came)
        else if (came != "") out("medium", k, "maintainers", mnt["o", k], mnt["n", k], "joined " came)
        else out("medium", k, "maintainers", mnt["o", k], mnt["n", k], "left " gone (index(mnt["n", k], ";") ? "" : " - one maintainer remains"))
      }
      if (known(pbl["o", k]) && known(pbl["n", k]) && pbl["o", k] != pbl["n", k]) {
        foreign = known(mnt["o", k]) && !inlist(pbl["n", k], mnt["o", k])
        if (pbl["n", k] == "GitHub Actions")   # npm trusted publishing: releases built and signed in CI
          out("medium", k, "publisher", pbl["o", k], pbl["n", k], "now published from CI (npm trusted publishing) - usually an improvement; confirm the workflow belongs to the project")
        else
          out(foreign ? "high" : "medium", k, "publisher", pbl["o", k], pbl["n", k], foreign ? "published by an account that was not a maintainer last time" : "")
      }
      if (known(rep["o", k]) && known(rep["n", k]) && rep["o", k] != rep["n", k]) out("medium", k, "repo", rep["o", k], rep["n", k], "source repository moved - confirm it is the same project")
      if (known(vul["o", k]) && known(vul["n", k]) && vul["o", k] != vul["n", k]) {
        o2 = (vul["o", k] == "none") ? "" : vul["o", k]; n2 = (vul["n", k] == "none") ? "" : vul["n", k]
        nw = minus(n2, o2); fx = minus(o2, n2)
        if (nw != "") out("high", k, "vulns", vul["o", k], vul["n", k], "new: " nw)
        if (fx != "") out("info", k, "vulns", vul["o", k], vul["n", k], "resolved: " fx)
      }
      if (known(loc["o", k]) && known(loc["n", k]) && loc["o", k] != loc["n", k])
        out(loc["n", k] == "modified" || loc["n", k] == "missing" ? "high" : "info", k, "local", loc["o", k], loc["n", k], "vendored copy " loc["n", k])
      # Crossed the 2-year line without a release since the last run.
      po = days(pub["o", k]); pn = days(pub["n", k]); to = days(gen["o"])
      if (pn > 0 && today > 0 && to > 0 && pub["o", k] == pub["n", k] && today - pn > 730 && to - po <= 730)
        out("medium", k, "stale", pub["n", k], (today - pn) " days", "no upstream release for 2 years")
    }
    nc = 0; for (k in changed) nc++
    print "SUMMARY|" add + 0 "|" rem + 0 "|" nc - add - rem "|" hi + 0 "|" me + 0
  }' "$OLD" "$NEW" | awk -F'|' '
    # Order: high, medium, info; then project, package.
    /^CHANGE/ { o = ($2 == "high" ? 1 : $2 == "medium" ? 2 : 3); print o "|" $0; next } { print "9|" $0 }' |
  LC_ALL=C sort -t'|' -k1,1n -k4,4 -k5,5 | cut -d'|' -f2-
