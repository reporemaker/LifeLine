# Report Format Reference

Every file LifeLine writes goes into one folder at the project root, `LifeLine_Report/`
(created when missing). File names inside are fixed and English. The folder is a
history: the first report is kept for good, the latest report is always complete, and
every run in between leaves a short record of what changed.

```
LifeLine_Report/
├── dependency-report.md          latest full report - overwritten every run
├── baseline-2026-10-24.md        first full report - written once, never touched again
├── timeline.md                   long view per dependency - regenerated every run
├── changes/
│   ├── 2026-11-24-changes.md     what changed in that run - important items only
│   └── 2026-12-24-changes.md
└── state/
    ├── 2026-10-24.tsv            machine snapshot of every run, the first one included
    ├── 2026-11-24.tsv
    └── 2026-12-24.tsv
```

| File | Written | Content |
|---|---|---|
| `dependency-report.md` | every run | full report (sections below) |
| `baseline-<date>.md` | first run only | a copy of that run's full report; the reference point "since the start" |
| `changes/<date>-changes.md` | every run after the first | not a full report: only what needs attention (format below) |
| `timeline.md` | every run after the first | per dependency, every step of every important field across all runs (format below) |
| `state/<date>.tsv` | every run | `snapshot-state.sh` output, saved as is - the data every comparison is made from |
| `sbom.cdx.json`, `dependency-report.json` | only if the user picks them after the report | |

Rules:

- `<date>` is the run date, `YYYY-MM-DD`. A second run on the same day appends `-2`,
  `-3` (`state/2026-10-24-2.tsv`, `changes/2026-10-24-2-changes.md`). Nothing is ever
  overwritten except `dependency-report.md` and `timeline.md`.
- Snapshots are taken on a full run and on `deps`; `map`, `services` and `vendored`
  runs read history but add nothing to it.
- **Comparisons come from the snapshots, never from re-reading old Markdown.** Previous
  run = the newest `state/*.tsv` before this one; baseline = the oldest.
- **Migrating an older folder.** A `dependency-report.md` (or the pre-1.1
  `docs/dependency-report.md`) without a `state/` folder: copy it to
  `baseline-<its Generated date>.md` before writing anything, say in the report that
  the baseline has no snapshot, and start `state/` with this run. The first change
  report then appears on the next run.
- Keep everything. Snapshots are small (a few hundred KB for a large tree); the history
  is the point. Recommend committing the folder; never commit it yourself.

`VENDORED.md` is the exception: it lives at the project root, next to the code it
describes, because it is a ledger the team maintains, not a generated report.

Structure and field names are stable across languages; prose follows the user's
language. Sections of the full report, in order:

## 1. Header

```markdown
# Dependency Report — <project name>
Generated: <date> · Scope: <full | map | deps | services | vendored>
Ecosystems: <list> · Previous report: <date | none>
```

## 2. Context Map

- Ecosystems found (with manifest paths)
- Module/layer overview (short — structure, not a code review)
- Module → external dependency table (the import map)

## 3. External Code Inventory

One table for packages, one for toolchain, one for assets:

```markdown
| Package | Version | Direct? | Used? | License | Last release | Risk signals | Criticality |
|---|---|---|---|---|---|---|---|
| express | 4.19.2 | direct | yes (7 modules) | MIT | 2025-03 | — | HIGH |
| left-pad | 1.3.0 | direct | yes (1 module, 1 fn) | WTFPL | 2018-04 | deprecated · archived | LOW |
```

`Last release` and the health part of `Risk signals` come from `upstream-health.sh`;
`unknown` when it could not be checked (say why in Limits).

Findings called out below the tables, each with severity:
- 🔴 phantom dependency (imported, not declared) · copyleft license · known CVE ·
  unpinned CI action / `latest` base image · CDN script without SRI · `curl | bash` in CI ·
  vendored code changed without a `Modifications` note
- 🟡 declared-but-unused · stale upstream (>2y) · deprecated · archived repo · single
  maintainer · install-time script (`preinstall`/`install`/`postinstall`) · unknown
  license · missing lock file · built-in replacement available
- ⚪ informational

## 4. Criticality rubric

Score each **direct** dependency on two axes:

| Axis | LOW | MED | HIGH |
|---|---|---|---|
| Usage breadth | 1 module | 2–5 modules | >5 modules or an entry point |
| Replacement cost | few lines of its API used — rewritable in a day | moderate surface | framework/deep integration — replacement is a project |

Criticality = the higher of the two. HIGH items are the "held hostage" list —
they lead the report summary. LOW×LOW items with unhealthy upstream feed Step 3
(vendoring/rewrite candidates).

## 5. External Services

```markdown
| Service | Referenced in | Credential | If it disappears |
|---|---|---|---|
| api.stripe.com | src/billing.ts, .env.example (STRIPE_KEY) | yes | payments stop |
```

## 6. Recommendations

Per candidate: verdict table (**replace with built-in** / vendor / pin / fork / rewrite),
license gate result, measured cost, the security trade-off sentence (see vendoring.md).
Explicitly labeled as recommendations awaiting a human decision.

```markdown
| Package | Verdict | Built-in | Total lines | Needed (reachable) | Used API | Pulls in | License |
|---|---|---|---|---|---|---|---|
| left-pad | replace with built-in | `padStart` (ES2017) | 210 | 52 | default fn, 1 file | 0 | WTFPL ✅ |
| rimraf | replace with built-in | `fs.rm` (Node 14.14) | 2158 | 999 | `rimraf`, 1 file | 40 | ISC ✅ |
```

`Total lines`, `Needed`, `Pulls in` from `measure-package.sh`; `Used API` from `used-api.sh`.

## 7. Vendor Tracking

Ledger status from Step 4: per entry — recorded version, latest upstream, OSV result,
status, local integrity (`unchanged` / `modified` / `missing` / `untracked`). For every
`update-available` / `cve-warning` entry: the patch proposal built from
`upstream-diff.sh` (what changed upstream, how it lands on our copy). If offline: **"Vendor check NOT performed (no network). Last successful check:
<date>."** as a visible warning block, never a footnote.

## 8. Changes since last report (only when a previous snapshot exists)

Three to six bullets from `diff-state.sh <previous> <now>`: the high items, counts for
the rest, and a link to `changes/<date>-changes.md`. The full report does not repeat
the change report — it points to it.

## 9. Limits of This Analysis

Always present. State concretely: dynamic imports not traced; ecosystems analyzed
without their native tool (incomplete transitive sets); CVE scan availability;
import-name mappings that were guessed.

---

# Change Report — `changes/<date>-changes.md`

Short and selective: a reader should see in a minute whether anything needs action.
Built from `diff-state.sh` (previous → now, baseline → now) and `timeline.sh`.

```markdown
# Change Report — <project> — <date>
Previous run: <date> · Baseline: <date> · Runs so far: <n>

## Needs attention
<every high item since the previous run, one bullet each: what changed, why it matters,
what to check. "Nothing needs attention." when empty.>

## Since the previous run
| Severity | Project | Package | What changed | Before → now |
<medium items; info items only for direct and vendored packages. Transitive dev-only
version bumps are counted, not listed: "118 dev-only transitive updates".>

## Since the baseline (<date>)
<high and medium items of baseline → now that are still true today, one table. This
catches slow changes that never looked big from one month to the next.>

## Ongoing changes
<for every package that has an important timeline (maintainers, publisher, repo,
license, install, archived, deprecated, scope, vulns), its steps from timeline.sh:>
- `event-pipe` maintainers: alice (2022-10) → alice, bob (2023-10) → bob (2024-10) →
  bob, gina (2025-10) → gina (2026-10). Publisher alice → bob → gina. Repository moved
  twice. Install script since 2025-10. Reads as a full handover; check the 2025 release.

## Quiet
<one line: "<n> packages unchanged since the previous run.">

## Limits
<what this run could not check: offline, unsupported lock files, "-" fields.>
```

Severity mapping: `high` → 🔴, `medium` → 🟡, `info` → ⚪.

What counts as high (from `diff-state.sh`): a maintainer handover (some left, some
joined), a publisher who was not a maintainer before, a new install script, a new
known vulnerability, a license turning copyleft, a vendored copy modified or missing, a
new package that runs an install script.

# Timeline — `timeline.md`

The long view, regenerated from all snapshots on every run. One section per package
that changed in an important field at least once, most recently changed first.

```markdown
# Dependency Timeline — <project>
Runs: <n> · <first date> → <last date>

## event-pipe (direct-runtime, `.`)
| Field | Steps |
|---|---|
| maintainers | 2022-10-24 alice → 2023-10-24 alice, bob → 2024-10-24 bob → 2025-10-24 bob, gina → 2026-10-24 gina |
| publisher | 2022-10-24 alice → 2024-10-24 bob → 2025-10-24 gina |
| repo | github.com/alice/… → 2024-10-24 github.com/bob/… → 2026-10-24 github.com/gina/… |
| install | 2022-10-24 no → 2025-10-24 yes |
| vulns | 2022-10-24 none → 2026-10-24 GHSA-… |

Reading: <one or two sentences — what the steps add up to.>
```

- Important fields: maintainers, publisher, repo, license, install, archived, deprecated,
  scope, vulns, local. `version` and `latest` only for direct and vendored packages.
- Packages that came or went (`PRESENCE` lines) get a line each in a final
  "Arrivals and departures" section; runtime arrivals first.
- Gaps (`-`, `unknown`) are not steps. A field that could not be collected in some runs
  says so: "not collected 2025-03 → 2025-06 (offline)".

---

# Optional Output Formats

Generated only when the user picks them after seeing the MD report.

## CycloneDX SBOM — `LifeLine_Report/sbom.cdx.json`

Minimal valid shape (CycloneDX 1.5, JSON):

```json
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "metadata": {
    "timestamp": "<ISO-8601>",
    "component": { "type": "application", "name": "<project>" },
    "tools": [ { "name": "LifeLine", "version": "1.1.0" } ]
  },
  "components": [
    {
      "type": "library",
      "name": "express",
      "version": "4.19.2",
      "purl": "pkg:npm/express@4.19.2",
      "licenses": [ { "license": { "id": "MIT" } } ],
      "scope": "required"
    }
  ]
}
```

- `purl` prefixes: `pkg:npm/`, `pkg:pypi/`, `pkg:golang/`, `pkg:cargo/`, `pkg:maven/<group>/`,
  `pkg:composer/`, `pkg:gem/`, `pkg:nuget/`, `pkg:docker/`, `pkg:github/<owner>/<repo>@<ref>`
  (use `pkg:github` for CI actions and vendored entries).
- Include vendored code from `VENDORED.md` as components with
  `"properties": [{ "name": "lifeline:vendored", "value": "true" }]`.
- `scope`: `"required"` for runtime deps, `"optional"` for dev/build.

## JSON export — `LifeLine_Report/dependency-report.json`

```json
{
  "generated": "<ISO-8601>",
  "project": "<name>",
  "ecosystems": ["npm", "pypi"],
  "dependencies": [
    { "name": "", "version": "", "ecosystem": "", "direct": true, "used": true,
      "usedBy": ["src/a.ts"], "license": "", "risks": [], "criticality": "HIGH|MED|LOW" }
  ],
  "toolchain": [ { "kind": "ci-action|docker-image|build-tool", "name": "", "ref": "", "pinned": true } ],
  "assets": [ { "url": "", "kind": "cdn-script|font|model|dataset", "sri": false } ],
  "services": [ { "host": "", "referencedIn": [], "credential": "", "impact": "" } ],
  "vendored": [ { "name": "", "version": "", "status": "", "local": "", "lastChecked": "" } ],
  "findings": [ { "severity": "high|medium|info", "message": "" } ],
  "limits": [ "" ]
}
```

Field names are fixed (they are an interface for downstream tools); values follow the data.
