# Vendoring Reference

Rules for recommending, executing (only with user approval), and recording vendoring —
moving external code into the repo to remove an outside dependence.

## Candidate profile

A dependency is a vendoring candidate when **most** of these hold:

| Signal | Threshold |
|---|---|
| Size | ≈ a few hundred lines actually needed (not the whole package — the used part) |
| API usage | The project uses a small fraction of the package (from the criticality analysis) |
| Upstream health | Unmaintained (>2y no release), archived, or single-maintainer |
| Change rate | Stable — code that rarely needs updates loses little by leaving upstream |
| Security surface | Low — pure logic, no parsing of untrusted input, no crypto, no network |

**Never a candidate**: frameworks, crypto libraries, anything parsing untrusted input
(those need upstream security patches), packages under copyleft licenses (below).

## License gate — MANDATORY, runs before any recommendation

| License | Verdict |
|---|---|
| MIT, BSD, ISC, Apache-2.0, Zlib, Unlicense/CC0 | ✅ Vendorable. Attribution required: keep the original license header/file with the copied code. Apache-2.0 additionally: keep NOTICE if present. |
| MPL-2.0, EPL | ⚠️ File-level copyleft — vendorable but modified files must stay under the original license. Flag clearly; recommend only if the user understands. |
| GPL-2.0/3.0, AGPL, SSPL, EUPL | ❌ Do NOT recommend vendoring. Copying this code into the project can impose the license on the whole project. State this risk explicitly in the report. |
| No license / unknown | ❌ Do NOT recommend. No license = no right to copy. Suggest contacting the author or finding an alternative. |

## The trade-off — always state it

Vendored code **stops receiving upstream patches**. A CVE published after vendoring will
not arrive via `npm audit`/Dependabot — nothing watches copied code except the lifeline
ledger. Every vendoring recommendation must carry this sentence in substance:
*"After vendoring, VENDORED.md + lifeline's Step 4 is the only thing standing between
this code and silent rot."*

## Alternatives — present alongside every candidate

1. **Pin** — exact version + lock file. Cheapest; upstream risk remains but is frozen.
2. **Fork** under the user's org — upstream disappears, your copy survives; you can still
   merge upstream fixes. Middle ground.
3. **Rewrite** — for micro-packages, writing the needed few lines yourself is often
   cleaner than vendoring: no license baggage, no ledger entry, one less external thing.

## Executing an approved vendoring (user said yes — only then)

1. Copy only what is needed, into a clearly marked location (e.g. `src/vendor/<name>/`).
2. Keep the original license text with the code (header comment or LICENSE file alongside).
3. **In the same change**, add the ledger entry to `VENDORED.md` (template below).
   A vendoring action without a ledger entry is an incomplete action — never skip this.
4. Remove the original dependency from the manifest (with user approval) and note the
   replacement in the report.

## VENDORED.md — ledger template

Lives at the project root. One `## <name>` section per vendored item. Field lines are
machine-parsed by `scripts/check-vendored.sh` — keep the exact `- Key: value` format.

```markdown
# VENDORED.md — Vendored Code Ledger

Code copied into this repo from outside. Every entry is checked for upstream updates
and CVEs by the lifeline skill (Step 4). Do not remove entries whose code still exists.

## left-pad
- Source: https://github.com/left-pad/left-pad
- Ecosystem: npm
- Package-Name: left-pad
- Version: 1.3.0
- Vendored-Date: 2026-07-28
- License: MIT
- Attribution: license header kept in file
- Location: src/vendor/left-pad/index.js
- Reason: 40 lines used; upstream unmaintained since 2018
- Last-Checked: 2026-07-28
- Status: current
```

Field notes:
- `Ecosystem` / `Package-Name`: registry identity for OSV queries (`npm`, `PyPI`,
  `crates.io`, `Go`, `Maven`, `Packagist`, `RubyGems`, `NuGet`). Use `none` when the code
  never lived in a registry (a gist, a blog snippet) — OSV check is skipped, upstream
  check still runs against `Source`. The upstream check understands GitHub sources
  only; any other `Source` comes back `unchecked`, and the report says so.
- `Version`: registry version or upstream commit hash — whatever was actually copied.
- `Status`: `current` | `update-available` | `cve-warning` — written by Step 4.
  `current` means every check that applies to the entry actually ran. When one could
  not run (offline, OSV request failed, non-GitHub `Source`) the entry is reported as
  `unchecked`; `unchecked` is never written to the ledger — the last known status stays.
- `Last-Checked`: updated by Step 4 on every successful check. If the project has no
  network, the date visibly ages — that is the feature.
