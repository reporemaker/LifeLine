# Report Format Reference

Every file LifeLine writes goes into one folder at the project root, `LifeLine_Report/`
(created when missing). File names inside are fixed and English. The folder is a
history (the first report kept for good, the latest always complete, a short record of
every run in between) and it is split in two:

- **Public** — safe to commit and publish. What the project depends on, licenses,
  health, history, and vulnerabilities that are already **closed**.
- **Private** — `LifeLine_Report/private/`. Everything that would help an attacker
  choose where to strike. **Never committed, never pushed, never published.** It goes
  to the customer only, outside GitHub: USB stick, encrypted e-mail, or by hand.

```
LifeLine_Report/
├── .gitignore                    written by LifeLine: "private/" - keeps it out of git
├── dependency-report.md          PUBLIC latest full report - overwritten every run
├── baseline-2026-10-24.md        PUBLIC first full report - written once, never touched again
├── timeline.md                   PUBLIC long view per dependency (no vulnerability history)
├── changes/
│   └── 2026-11-24-changes.md     PUBLIC what changed in that run - important items only
├── state/
│   └── 2026-11-24.tsv            PUBLIC snapshot (vulns column "-")
└── private/                      PRIVATE - never leaves the team and the customer
    ├── sensitive-report.md       latest sensitive report
    ├── baseline-2026-10-24-sensitive.md
    ├── changes/2026-11-24-sensitive.md
    ├── timeline-sensitive.md     vulnerability history per package
    └── state/2026-11-24.tsv      full snapshot, vulnerability ids included
```

| File | Written | Content |
|---|---|---|
| `.gitignore` | when missing | one line: `private/` |
| `dependency-report.md` | every run | public full report (sections below) |
| `baseline-<date>.md` | first run only | copy of that run's public report |
| `changes/<date>-changes.md` | every run after the first | public change report (format below) |
| `timeline.md` | every run after the first | public timeline (`timeline.sh state public`, format below) |
| `state/<date>.tsv` | every run | `snapshot-state.sh --public` of the private snapshot |
| `private/sensitive-report.md` | every run | sensitive report (format below) |
| `private/baseline-<date>-sensitive.md` | first run only | copy of that run's sensitive report |
| `private/changes/<date>-sensitive.md` | every run after the first | sensitive changes: vulnerabilities opened/closed, new weak points |
| `private/timeline-sensitive.md` | every run after the first | vulnerability steps per package from `timeline.sh private/state private` |
| `private/state/<date>.tsv` | every run | `snapshot-state.sh` output as is |
| `sbom.cdx.json`, `dependency-report.json` | only if the user picks them | public content only |

## What is sensitive

One item alone is rarely a leak. Put together they read like a list of where it would
hurt most to strike. These go to `private/` only, and the public report says nothing
about them — **not even how many there are** (a count is a signal too):

1. **Open vulnerabilities** — ids, affected packages and versions, which ones reach users.
2. **Failure impact and resilience** — what breaks if a service disappears, single
   points of failure, how backups are made, where they live, how often, recovery limits.
3. **Secrets and access** — which secrets exist and what they unlock, bypass flags
   (`SKIP_ACCESS`-style), access policies and the accounts in them, rate-limit thresholds.
4. **Attack paths in the toolchain** — deploys or tools that run unpinned code
   ("production is deployed with whatever `wrangler` is latest that day"), unpinned
   install steps that run with the developer's rights.

Not sensitive (stays public): host names and subdomains already in the repo, the list of
services and that they need a credential, licenses, health, criticality, closed
vulnerabilities.

Rules:

- `<date>` is the run date, `YYYY-MM-DD`. A second run on the same day appends `-2`,
  `-3`. Nothing is ever overwritten except `dependency-report.md`, `timeline.md`,
  `private/sensitive-report.md` and `private/timeline-sensitive.md`.
- Snapshots are taken on a full run and on `deps`; `map`, `services` and `vendored`
  runs read history but add nothing to it.
- **Comparisons come from the snapshots, never from re-reading old Markdown.** Public
  reports compare public snapshots; private reports compare private ones. Previous run
  = the newest snapshot before this one; baseline = the oldest.
- **`.gitignore` first.** Before the first file goes into `private/`, make sure
  `LifeLine_Report/.gitignore` contains `private/`. If the project's git already tracks
  a file under `private/`, stop and tell the user — ignoring does not untrack.
- **Migrating an older folder.** A `dependency-report.md` (or one at the old location
  `docs/dependency-report.md`) without `state/`: it may contain sensitive items. Move it
  to `private/baseline-<its Generated date>-sensitive.md`, write a public
  `baseline-<date>.md` from it with the sensitive parts removed, say in the report that
  the baseline has no snapshot, and start both `state/` folders with this run.
- Keep everything. Recommend committing the public part; never commit anything yourself.

`VENDORED.md` is the exception: it lives at the project root, next to the code it
describes, because it is a ledger the team maintains, not a generated report.

Structure and field names are stable across languages; prose follows the user's
language. Sections of the **public** full report, in order:

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

Findings called out below the tables, each with severity. Open vulnerabilities and
unpinned deploy/tool paths are **not** listed here — they go to the sensitive report;
the public report does not hint at them, not even with a count.
- 🔴 phantom dependency (imported, not declared) · copyleft license ·
  CDN script without SRI · vendored code changed without a `Modifications` note
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
| Service | Referenced in | Credential |
|---|---|---|
| api.stripe.com | src/billing.ts, .env.example (STRIPE_KEY) | yes |
```

"If it disappears", backups, single points of failure: sensitive report only. Name a
credential only the way a committed file already names it (`.env.example`, a config
key); what a secret unlocks, and secrets known only from outside the repo (a deploy
dashboard, the user's description) go to the sensitive report.

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

Ledger status from Step 4: per entry — recorded version, latest upstream, version
status (`current` / `update-available` / `unchecked`), local integrity (`unchanged` /
`modified` / `missing` / `untracked` / `unknown`). Nothing about vulnerabilities and no
patch proposals: every entry gets the same columns. Advisories and all patch proposals
(from `upstream-diff.sh`) are in the sensitive report. If offline: **"Vendor check NOT performed (no network). Last successful check:
<date>."** as a visible warning block, never a footnote.

## 8. Closed vulnerabilities (responsible disclosure)

Every vulnerability that was found by an earlier run and is gone now, from
`disclosure.sh LifeLine_Report/private/state` (`CLOSED` lines only — `OPEN` and
`REOPENED` lines never appear in a public file). Cumulative: the whole record, newest
closures first. Rows from earlier runs are kept as they are, even when the script no
longer prints that id: an advisory that came back is a `REOPENED` line for the
sensitive report, and dropping its old row here would reveal exactly that.

```markdown
| Advisory | Package | Project | Found | Closed | Days open |
|---|---|---|---|---|---|
| GHSA-xxxx-xxxx-xxxx | vite | `.` | 2026-10-24 | 2026-11-02 | 9 |
```

None closed yet → one line: "No vulnerability has been closed yet." Never add anything
that hints at open ones.

## 9. Changes since last report (only when a previous snapshot exists)

Three to six bullets from `diff-state.sh` on the two newest **public** snapshots, plus
vulnerabilities closed in this run, and a link to `changes/<date>-changes.md`.

## 10. Limits of This Analysis

Always present. State concretely: dynamic imports not traced; ecosystems analyzed
without their native tool (incomplete transitive sets); CVE scan availability;
import-name mappings that were guessed.

## 11. Sensitive report

Always the last section, always in this wording (translated to the report language):

```markdown
## Sensitive report

A sensitive report was produced in this run. It is not part of this repository and is
delivered to the customer outside GitHub.

Generated: 2026-11-24 · sha256: 3f2a…c9e1
```

The hash is `check-vendored.sh --hash <root> LifeLine_Report/private/sensitive-report.md`.
The recipient computes the same hash on the file they received; equal hashes prove it is
the file from this run, unchanged. Nothing else about its content is stated here.

---

# Sensitive Report — `private/sensitive-report.md`

Starts with this notice, always, verbatim in English and then in the report language:

```markdown
> **CONFIDENTIAL — DO NOT COMMIT, DO NOT PUSH, DO NOT PUBLISH.**
>
> This file lists the open weak points of <project>: unfixed vulnerabilities, what
> breaks when a service disappears, how backups and secrets are handled, and which
> tools run unpinned code. None of these is a leak on its own. Put together, they read
> like a map of where an attack would hurt most.
>
> Keep it out of every repository, issue tracker, chat and shared drive. Deliver it to
> the customer only: on a USB stick, by encrypted e-mail, or by hand. It is listed in
> `LifeLine_Report/.gitignore` so git skips it — check that before every commit.
```

Then:

```markdown
# Sensitive Report — <project>
Generated: <date> · Belongs to: LifeLine_Report/dependency-report.md of the same date

## Open vulnerabilities
| Advisory | Package | Project | Scope | Found | Days open | Reaches users? | Fix |

## Failure impact and resilience
| Service | If it disappears | Backup / recovery |
<single points of failure, backup method and limits>

## Secrets and access
<secrets and what they unlock, bypass flags, access policies, thresholds>

## Attack paths in the toolchain
<unpinned deploys and tools, install steps with developer rights>

## What to do first
<ordered list>
```

Sensitive change report (`private/changes/<date>-sensitive.md`): the same notice, then
vulnerabilities opened and closed since the previous run (`diff-state.sh` on the two
newest private snapshots, `vulns` lines) and any new item in the four sensitive groups.

---

# Change Report — `changes/<date>-changes.md` (public)

Short and selective: a reader should see in a minute whether anything needs action.
Built from `diff-state.sh` on **public** snapshots (previous → now, baseline → now),
`timeline.sh LifeLine_Report/state public`, and the `CLOSED` lines of `disclosure.sh` for this
run. Open vulnerabilities never appear here; closed ones do, with their dates.

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
license, install, archived, deprecated, scope, local), its steps from timeline.sh:>
- `event-pipe` maintainers: alice (2022-10) → alice, bob (2023-10) → bob (2024-10) →
  bob, gina (2025-10) → gina (2026-10). Publisher alice → bob → gina. Repository moved
  twice. Install script since 2025-10. Reads as a full handover; check the 2025 release.

## Closed vulnerabilities
<CLOSED lines of disclosure.sh whose closed-on is this run: advisory, package, found,
closed, days open. "None closed in this run." otherwise. Never anything about open ones.>

## Quiet
<one line: "<n> packages unchanged since the previous run.">

## Limits
<what this run could not check: offline, unsupported lock files, "-" fields.>
```

Severity mapping: `high` → 🔴, `medium` → 🟡, `info` → ⚪.

What counts as high (from `diff-state.sh`): a maintainer handover (some left, some
joined), a publisher who was not a maintainer before, a new install script, a license
turning copyleft, a vendored copy modified or missing, a new package that runs an install
script. A new known vulnerability is high too, but it is reported in the private change
report only.

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

Reading: <one or two sentences — what the steps add up to.>
```

- Important fields: maintainers, publisher, repo, license, install, archived, deprecated,
  scope, local. Vulnerability history (`vulns`) is in `private/timeline-sensitive.md`
  only — the public snapshots do not even contain it. `version` and `latest` only for direct and vendored packages.
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
    "tools": [ { "name": "LifeLine", "version": "1.0.3" } ]
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
- Public content only: no vulnerability data in the SBOM or the JSON export.
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
  "services": [ { "host": "", "referencedIn": [], "credential": "" } ],
  "vendored": [ { "name": "", "version": "", "versionStatus": "current|update-available|unchecked", "local": "", "lastChecked": "" } ],
  "findings": [ { "severity": "high|medium|info", "message": "" } ],
  "limits": [ "" ]
}
```

Field names are fixed (they are an interface for downstream tools); values follow the data.
