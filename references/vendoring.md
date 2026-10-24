# Vendoring Reference

Rules for recommending, executing (only with user approval), and recording vendoring —
moving external code into the repo to remove an outside dependence.

## Candidate profile

A dependency is a vendoring candidate when **most** of these hold:

| Signal | Threshold |
|---|---|
| Size | Under ≈ 500 lines actually needed — the *reachable* figure from `measure-package.sh`, not the package total |
| API usage | The project uses a small fraction of the package (`used-api.sh`) |
| Weight | Bonus: it pulls in other packages (`measure-package.sh` transitive count) — dropping it removes those too |
| Upstream health | Unmaintained (>2y no release), archived, or single-maintainer |
| Change rate | Stable — code that rarely needs updates loses little by leaving upstream |
| Security surface | Low — pure logic, no parsing of untrusted input, no crypto, no network |

**Never a candidate**: frameworks, crypto libraries, anything parsing untrusted input
(those need upstream security patches), packages under copyleft licenses (below).

**Before vendoring, check [replacements.md](replacements.md).** If the runtime has a
built-in for it, deleting the dependency beats copying it.

## License gate — MANDATORY, runs before any recommendation

| License | Verdict |
|---|---|
| MIT, BSD, ISC, Apache-2.0, Zlib, Unlicense/CC0, WTFPL, BlueOak-1.0.0 | ✅ Vendorable. Attribution required: keep the original license header/file with the copied code. Apache-2.0 additionally: keep NOTICE if present. |
| MPL-2.0, EPL | ⚠️ File-level copyleft — vendorable but modified files must stay under the original license. Flag clearly; recommend only if the user understands. |
| GPL-2.0/3.0, AGPL, SSPL, EUPL | ❌ Do NOT recommend vendoring. Copying this code into the project can impose the license on the whole project. State this risk explicitly in the report. |
| No license / unknown | ❌ Do NOT recommend. No license = no right to copy. Suggest contacting the author or finding an alternative. |

## The trade-off — always state it

Vendored code **stops receiving upstream patches**. A CVE published after vendoring will
not arrive via `npm audit`/Dependabot — nothing watches copied code except the LifeLine
ledger. Every vendoring recommendation must carry this sentence in substance:
*"After vendoring, VENDORED.md + LifeLine's Step 4 is the only thing standing between
this code and silent rot."*

## Alternatives — present alongside every candidate

1. **Pin** — exact version + lock file. Cheapest; upstream risk remains but is frozen.
2. **Fork** under the user's org — upstream disappears, your copy survives; you can still
   merge upstream fixes. Middle ground.
3. **Rewrite** — for micro-packages, writing the needed few lines yourself is often
   cleaner than vendoring: no license baggage, no ledger entry, one less external thing.

## Vendor only what is used

The goal is the smallest copy that keeps today's behaviour, not a mirror of the package.

1. `used-api.sh <root> <pkg>` → the exports and members the project touches.
2. `measure-package.sh <root> <pkg>` → entry file and reachable files (file level).
3. In those files, start from the used exports and follow what they call inside the
   package: helper functions, constants, internal requires. Stop at what is not reached.
4. Copy that slice. Keep the package's structure where it helps a later diff (same file
   names), or one file when the slice is small — then record `Upstream-Path`.
5. Run the project's tests. A slice that breaks a test was cut too thin.
6. Say in the report what was left out ("copied 52 of 210 lines: `leftPad`, cache table;
   left out: typings, benchmarks").

## Executing an approved vendoring (user said yes — only then)

1. Copy only what is needed (above), into a clearly marked location (e.g. `src/vendor/<name>/`).
2. Keep the original license text with the code (header comment or LICENSE file alongside).
3. Point the project's imports at the copy (`from 'left-pad'` → `from './vendor/left-pad.js'`).
4. Record the checksum: `check-vendored.sh --hash <root> <location>` → the `Checksum` value.
5. **In the same change**, add the ledger entry to `VENDORED.md` (template below).
   A vendoring action without a ledger entry is an incomplete action — never skip this.
6. Remove the original dependency from the manifest (with user approval) and note the
   replacement in the report.

## Changing vendored code later

Vendored code may be changed on purpose (a bug fix, a backported patch). Every change
needs, in the same commit: a line in `Modifications`, and a fresh `Checksum`. A
checksum mismatch without a `Modifications` note is reported as a 🔴 finding —
nobody can tell a deliberate fix from an accident, or from tampering.

## Patch help — when upstream moves

For an entry that is `update-available` or `cve-warning`:

1. `upstream-diff.sh <root> <entry> [version]` → `upstream.diff` (recorded → new) and
   `local.diff` (recorded → our copy), in a temp dir.
2. Keep only the upstream hunks that touch the part we copied.
3. Re-apply our local changes from `local.diff` on top, so neither side is lost.
4. Show the resulting patch. With approval: apply, run tests, update `Version`,
   `Checksum`, `Last-Checked`, and add a `Modifications` line if our changes were kept.

## VENDORED.md — ledger template

Lives at the project root. One `## <name>` section per vendored item. Field lines are
machine-parsed by `scripts/check-vendored.sh` — keep the exact `- Key: value` format.

```markdown
# VENDORED.md — Vendored Code Ledger

Code copied into this repo from outside. Every entry is checked for upstream updates
and CVEs by the LifeLine skill (Step 4). Do not remove entries whose code still exists.

## left-pad
- Source: https://github.com/stevemao/left-pad
- Ecosystem: npm
- Package-Name: left-pad
- Version: 1.3.0
- Vendored-Date: 2026-07-28
- License: WTFPL
- Attribution: license header kept in file
- Location: src/vendor/left-pad.js
- Upstream-Path: index.js
- Checksum: sha256:32641b6b3c2bd800bcc8283205ee27426aed2559f1e8eb7d9377530f62292686
- Modifications: none
- Reason: 52 lines reachable, 1 function used; upstream archived, deprecated since 2018
- Last-Checked: 2026-07-28
- Status: current
```

Field notes:
- `Ecosystem` / `Package-Name`: registry identity for OSV queries (`npm`, `PyPI`,
  `crates.io`, `Go`, `Maven`, `Packagist`, `RubyGems`, `NuGet`). Use `none` when the code
  never lived in a registry (a gist, a blog snippet) — OSV check is skipped, upstream
  check still runs against `Source`. Without a registry identity the upstream check
  understands GitHub sources only; any other `Source` comes back `unchecked`, and the
  report says so.
- `Version`: registry version or upstream commit hash — whatever was actually copied.
- `Location`: file or folder, relative to the project root.
- `Upstream-Path`: where `Location` came from inside the package, when the names differ
  (`left-pad.js` ← `index.js`). Lets `upstream-diff.sh` pair the files.
- `Checksum`: `sha256:` of `Location` from `check-vendored.sh --hash`. Step 4 compares it
  on every run, offline too.
- `Modifications`: `none`, or one line per deliberate change (date · what · why).
- `Status`: `current` | `update-available` | `cve-warning` — written by Step 4.
  `current` means every check that applies to the entry actually ran. When one could
  not run (offline, OSV request failed, no registry identity and a non-GitHub `Source`)
  the entry is reported as
  `unchecked`; `unchecked` is never written to the ledger — the last known status stays.
- `Last-Checked`: updated by Step 4 on every successful check. If the project has no
  network, the date visibly ages — that is the feature.
