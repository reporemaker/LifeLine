# Report Format Reference

Every file lifeline writes goes into one folder at the project root, `LifeLine_Report/`
(created when missing). File names inside are fixed and English:

| File | When |
|---|---|
| `LifeLine_Report/dependency-report.md` | every run |
| `LifeLine_Report/sbom.cdx.json` | only if the user picks it after the report |
| `LifeLine_Report/dependency-report.json` | only if the user picks it after the report |

`VENDORED.md` is the exception: it lives at the project root, next to the code it
describes, because it is a ledger the team maintains, not a generated report.

Structure and field names are stable across languages; prose follows the user's
language. Sections in order:

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

## 8. Changes since last report (only when a previous report exists)

Added / removed dependencies, criticality or risk changes, findings resolved / new.
Keep it a short bullet list — the delta, not a second report.

## 9. Limits of This Analysis

Always present. State concretely: dynamic imports not traced; ecosystems analyzed
without their native tool (incomplete transitive sets); CVE scan availability;
import-name mappings that were guessed.

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
    "tools": [ { "name": "lifeline", "version": "1.0.0" } ]
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
