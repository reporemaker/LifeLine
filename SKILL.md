---
name: lifeline
description: >-
  Audit and continuously track everything a project depends on from the outside:
  open-source packages (declared and actually used), toolchain dependencies (CI actions,
  Docker base images, build tools), CDN/asset dependencies, external services (APIs,
  databases, SaaS), and vendored code. Builds a context map, scores how critical each
  dependency is, checks licenses, upstream health and risk signals, measures what a
  package really costs (lines, reachable code, transitive weight), points to built-in
  replacements, advises on vendoring only the used part with a mandatory license gate,
  maintains a VENDORED.md ledger with upstream update, CVE, local-change tracking and
  patch help, and keeps a dated history (baseline, change reports, per-dependency
  timeline) so slow changes such as a maintainer handover show up across runs. Splits
  every report into a public part and a private part (open vulnerabilities, failure
  impact, secrets, attack paths) that is never committed and goes to the customer only.
  Use when asked to list dependencies, audit the supply chain, generate an SBOM,
  map external services, check vendored code, or assess how dependent a project is
  on outside code.
argument-hint: "[map|deps|services|vendored]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/snapshot-state.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/disclosure.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/diff-state.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/timeline.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/find-manifests.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/scan-imports.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/check-vendored.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/upstream-health.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/measure-package.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/used-api.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/upstream-diff.sh *)
---

# LifeLine — External Dependency Audit & Tracking

Every project survives on things it does not own: open-source packages, base images,
CI actions, CDN assets, third-party APIs, and code copied in from elsewhere. LifeLine
finds all of them, shows which ones truly hold the project hostage, and makes sure the
copied-in ones are never forgotten.

## Principles (non-negotiable)

1. **Audit and advise — never modify.** LifeLine never vendors, removes, upgrades, or
   rewrites anything on its own. It produces a report and recommendations; the human decides.
2. **Honest precision.** Static analysis misses dynamic imports (`importlib`, dynamic
   `import()`, reflection). Every report carries a "limits of this analysis" note.
3. **Graceful degradation, loud disclosure.** No ecosystem tool installed → fall back to
   reading lock files. No network → skip remote checks, but the report must state
   "vendor check NOT performed — last checked: <date>". Never skip silently.
4. **Report in the user's language.** Section structure and field names stay stable;
   prose follows the language the user speaks.
5. **Zero external dependence.** LifeLine itself needs nothing beyond standard Unix tools.
   Network calls (OSV, upstream checks) are optional enrichment, never a requirement.

## Invocation

`/lifeline [scope]` — no argument runs the **full audit** (all steps + report + ledger check).

| Argument | Scope |
|---|---|
| `map` | Step 0 only: context map |
| `deps` | Steps 0+1: context map + external code inventory |
| `services` | Steps 0+2: context map + external services |
| `vendored` | Step 4 only: vendor ledger check |
| *(none)* | Steps 0–4, full report, ledger check |

## Step 0 — Context Map

The foundation every other step builds on.

1. Run `${CLAUDE_SKILL_DIR}/scripts/find-manifests.sh <project-root>`.
   Output lines are `CATEGORY<TAB>path` with categories `MANIFEST`, `LOCK`, `CI`,
   `CONTAINER`, `LEDGER`. Multiple ecosystems in one repo (monorepo) → analyze each.
2. Identify the project's modules, layers, and entry points by reading the tree and
   key files (keep this proportionate — structure, not a full code review).
3. Run `${CLAUDE_SKILL_DIR}/scripts/scan-imports.sh <project-root>` to get the raw
   import and URL surface. Build the **module → external dependency map**: which module
   imports which outside package.

Deliverable: ecosystem list + module map + import map. This feeds criticality scoring in Step 1.

## Step 1 — External Code Inventory

Load [references/ecosystems.md](references/ecosystems.md) for per-ecosystem commands,
lock-file fallbacks, and import patterns. Then build the inventory:

1. **Declared dependencies** — from manifests and lock files. Prefer the ecosystem's own
   tool (`npm ls`, `pip list`/`pipdeptree`, `go mod graph`, `cargo tree`, …); if absent,
   parse the lock file directly. Mark each as *direct* or *transitive*.
2. **Actually used dependencies** — from the import scan. Cross-check against declared:
   - declared but never imported → *possibly removable*
   - imported but not declared → *phantom dependency* (works by accident; high risk)
3. **Toolchain dependencies** — CI workflow `uses:` actions, Docker `FROM` images,
   build tools and plugins. These are external code too and belong in the inventory.
4. **Asset dependencies** — CDN scripts/styles/fonts in HTML/templates, downloaded
   models or datasets (from the URL scan output).
5. **Licenses** — one license per dependency in the table; flag copyleft (GPL/AGPL/SSPL)
   prominently. Unknown license = a finding, not a blank cell.
6. **Risk signals** — per direct dependency, run
   `${CLAUDE_SKILL_DIR}/scripts/upstream-health.sh <ecosystem> <package>`
   (`HEALTH|eco|pkg|latest|published|age-days|deprecated|maintainers|repo|archived|install-scripts|licenses`).
   Flag: latest release older than 2 years, deprecated, archived repo, a single
   maintainer, and **install-time scripts** (`preinstall`/`install`/`postinstall` run
   code on every machine that installs the package — always list them). Also from the
   manifests: unpinned versions (`*`, `latest`, missing lock entry). Offline → the script
   says `OFFLINE`; put that in Limits, do not guess the fields.
   Known CVEs:
   use `npm audit` / `pip-audit` / `osv-scanner` **only if already installed**; otherwise
   note "CVE scan not available in this environment" in the report. Open
   vulnerabilities are **sensitive**: they go to `private/sensitive-report.md` only
   (see Report); the public report does not mention them, not even as a count.
7. **Criticality score** — for each direct dependency, apply the rubric in
   [references/report-format.md](references/report-format.md): usage breadth (how many
   modules import it) × replaceability (how much of its API surface is used). This answers
   the core question: *which dependency actually holds this project hostage?*

## Step 2 — External Services

Everything the project needs at runtime that is not code in the repo:

- **Endpoints**: external URLs in source/config (from the URL scan; ignore doc links).
- **Environment variables** that point to outside systems: `*_URL`, `*_HOST`, `*_API_KEY`,
  `*_TOKEN`, `*_DSN`, connection strings. Check `.env.example`, config files, deploy manifests.
- **Databases / queues / caches** — connection configs, ORM settings, client SDK usage.
- **SaaS integrations** — auth providers, payment, email, telemetry, error tracking SDKs.

Deliverable: a table — service, where it is referenced, credential required (public),
and **what breaks if this service disappears**, backups and recovery, secrets and access
details (sensitive report only).

## Step 3 — Recommendations & Vendoring Advisor

Load [references/vendoring.md](references/vendoring.md). For each dependency worth acting on:

0. **Built-in first** — match it against [references/replacements.md](references/replacements.md).
   If the language or runtime already does the job (`left-pad` → `padStart`), recommend
   deleting the dependency before any vendoring talk. Check the project's real minimum
   runtime first.
1. **Vendoring candidates** — measure, do not estimate:
   - `${CLAUDE_SKILL_DIR}/scripts/measure-package.sh <root> <package>` → total code lines,
     lines **reachable from the entry file**, direct and transitive dependency count.
     The reachable figure is what vendoring would really copy; the transitive count is
     what dropping the dependency would remove (a 50-line package that pulls in 40 others
     is a strong candidate).
   - `${CLAUDE_SKILL_DIR}/scripts/used-api.sh <root> <package>` → the exact exported names
     and members the project uses, per file.
   Candidate: needed code ≈ under 500 lines, a small part of the API used, unhealthy
   upstream (Step 1 health). For each: bring-in cost (low/med/high), license verdict,
   security trade-off (vendored code stops receiving upstream patches).
   **Vendor only what is used**: the copy is the used exports plus what they call inside
   the package — not the whole package (procedure in references/vendoring.md).
2. **License gate — mandatory.** Permissive (MIT/BSD/Apache/ISC) → vendorable with
   attribution. Copyleft (GPL/AGPL/SSPL) → **do not recommend vendoring**; state the
   contamination risk explicitly.
3. **Always present the alternatives** next to every vendoring suggestion:
   pin the version · fork under the user's org · rewrite the needed few lines and drop
   the dependency entirely (often the cleanest option for micro-packages).
4. **Never vendor automatically.** If — and only if — the user explicitly approves a
   vendoring action, perform it *and in the same change* add the entry to `VENDORED.md`
   using the template in references/vendoring.md. A vendoring action without a ledger
   entry is an incomplete action.

## Step 4 — Vendor Ledger Check

The step that makes sure copied-in code is never forgotten.

1. If `VENDORED.md` exists at the project root, run
   `${CLAUDE_SKILL_DIR}/scripts/check-vendored.sh <project-root>`.
   It parses each ledger entry and (network permitting) checks the upstream source for
   newer versions and queries the OSV database (api.osv.dev) for known vulnerabilities.
   Output lines: `ENTRY|name|recorded|latest|osv_hits|status|local|version` plus `OFFLINE`/`NOLEDGER` lines.
   `status` includes `cve-warning` and is for the **private** report only; `version`
   (`current` / `update-available` / `unchecked`) is about the upstream version alone.
   `local` compares the vendored files with the ledger's `Checksum` (works offline):
   `modified` = someone changed vendored code after it was recorded — report it as a
   finding unless the entry's `Modifications` field explains it.
2. Update each entry's `Last-Checked` date and `Status` field in `VENDORED.md`
   (this ledger update is the one file LifeLine is allowed to write besides the report).
   `VENDORED.md` is committed, so write the **`version`** field there, never `status`:
   the ledger must not hint at an open vulnerability. When `version` is `unchecked`
   (offline, or no upstream the script can read — neither a registry covered by
   deps.dev nor a GitHub source), leave `Status` and `Last-Checked` as they are; the
   date visibly ages.
3. Findings: the public **Vendor Tracking** section shows the version status and local
   integrity only. `cve-warning` entries, their advisory ids and every patch proposal for
   them go to the sensitive report only — the public report treats those entries like
   any other.
   **Patch help** — for every `update-available` or `cve-warning` entry run
   `${CLAUDE_SKILL_DIR}/scripts/upstream-diff.sh <root> <entry> [target-version]`.
   It writes `upstream.diff` (recorded → target) and `local.diff` (recorded → our copy)
   to a temp dir. Read both and propose a concrete patch for the vendored copy: the
   upstream change, adapted around our local changes (in the sensitive report if the
   entry has an open vulnerability). Show the patch; apply it only with
   approval, and in the same change update `Version`, `Checksum` and `Last-Checked`.
   Delete the `WORKDIR` it printed once the patch is proposed — it holds downloaded
   third-party archives.
4. **Offline**: add to the report — "Vendor check NOT performed (no network).
   Last successful check: <date>." Never silent.
5. No `VENDORED.md`, but the scan found copied-in third-party code (foreign license
   headers, `vendor/`-style folders outside package management)? Recommend creating the
   ledger and offer to draft it from what was found — with user approval.

## Report

Everything goes into `LifeLine_Report/` at the project root (create it if missing; file
names are always English), laid out in [references/report-format.md](references/report-format.md).
It is a history, and it is split:

- **public** files — safe to commit: full report, baseline, change reports, timeline,
  public snapshots, closed vulnerabilities;
- **`private/`** — open vulnerabilities, failure impact and backups, secrets and access,
  unpinned deploy/tool paths. **Never committed, never pushed, never published**; the
  customer gets it outside GitHub (USB stick, encrypted e-mail, by hand). The public
  files say nothing about it — no counts, no hints — except the seal (date + sha256).

On a full run (and on `deps`):

1. **Guard first.** Make sure `LifeLine_Report/.gitignore` contains `private/` (create it).
   If git already tracks anything under `LifeLine_Report/private/`, stop and tell the user.
2. **Snapshot.** `${CLAUDE_SKILL_DIR}/scripts/snapshot-state.sh <root>` → save as is to
   `private/state/<date>.tsv` (`<date>-2.tsv` for a second run that day). Then
   `snapshot-state.sh --public private/state/<date>.tsv` → `state/<date>.tsv`.
   Repeat every `# limit:` line in the report's Limits.
3. **Find the history.** Previous = newest other snapshot, baseline = oldest — public
   snapshots for public reports, private ones for private reports. No `state/` but an
   older report? Migrate it as report-format.md describes (it may hold sensitive items).
4. **Disclosure.** `${CLAUDE_SKILL_DIR}/scripts/disclosure.sh LifeLine_Report/private/state`:
   `CLOSED` lines may be published (Closed vulnerabilities section); `OPEN` lines go to
   the sensitive report only.
5. **Sensitive report.** Write `private/sensitive-report.md`, starting with the
   confidentiality notice from report-format.md, verbatim. On the first run also copy it
   to `private/baseline-<date>-sensitive.md`.
6. **Public full report.** Write `dependency-report.md` (Context Map → External Code
   Inventory → External Services → Recommendations → Vendor Tracking → Closed
   vulnerabilities → Changes since last report → Limits → Sensitive report seal). Nothing
   from the four sensitive groups, not even a count. On the first run also save it as
   `baseline-<date>.md`; never write to a baseline again.
7. **Change reports** (every run after the first). Public: `diff-state.sh` on public
   snapshots (previous → now, baseline → now) and `timeline.sh LifeLine_Report/state public` →
   `changes/<date>-changes.md`: what needs attention, what changed, what differs from the
   baseline, ongoing changes over several runs, vulnerabilities closed in this run.
   Private: `diff-state.sh` on private snapshots → `private/changes/<date>-sensitive.md`
   (vulnerabilities opened and closed, new weak points). Only important items.
8. **Timelines.** `timeline.md` from `timeline.sh LifeLine_Report/state public`;
   `private/timeline-sensitive.md` from `timeline.sh LifeLine_Report/private/state private`
   (the vulnerability steps).
9. **Check before you finish.** `grep` every public file for each `OPEN` advisory id and
   for the sensitive details you wrote into `private/`. Any hit is a bug — move it to
   `private/` before answering.

Comparisons always come from the snapshots, never from re-reading old Markdown. Never
overwrite a baseline, a change report or a snapshot. Never commit anything yourself;
recommend committing the public part, and remind the user how `private/` is delivered.

## After the Report — Output Format Question

The person running the skill decides the output format, not the skill. After writing
the Markdown report, ask exactly one question:

> The report is at `LifeLine_Report/dependency-report.md`. Do you want an additional format?
> 1. Markdown only — done (default)
> 2. CycloneDX SBOM (`LifeLine_Report/sbom.cdx.json`) — for security/compliance tooling
> 3. JSON export (`LifeLine_Report/dependency-report.json`) — for feeding other tools

Use the AskUserQuestion tool if available; otherwise ask in plain text. Generate the
extra format only after the user chooses it (schemas in references/report-format.md).

## Out of Scope — LifeLine will NOT

- vendor, remove, upgrade, or pin anything without explicit user approval
- generate application code or fix findings
- claim completeness it cannot verify (see Principle 2)
- require network access, paid tools, or any external skill to function
