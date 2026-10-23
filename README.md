<div align="center">

<a href="https://remaker.ch">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://remaker.ch/brand/remaker-logo-beyaz.png">
    <img src="https://remaker.ch/brand/remaker-logo.png" alt="RE*maker" height="44">
  </picture>
</a>

# lifeline

<p>A Claude Code skill that finds everything your project depends on from the outside, and keeps watching the code you copied in.</p>

</div>

## What it does

- **Maps** every outside dependency: packages (declared and actually imported), CI actions, Docker images, CDN assets, external services.
- **Scores** which dependency really holds the project hostage, with license and risk signals for each.
- **Advises** on small, stale packages: pin, fork, rewrite the few lines, or vendor. Copyleft code is never recommended for vendoring.
- **Tracks** vendored code in a `VENDORED.md` ledger and re-checks it on every run for upstream updates and known CVEs ([osv.dev](https://osv.dev)).

It audits and advises. It never changes your project on its own.

## Install

For all your projects:

```sh
git clone https://github.com/reporemaker/lifeline ~/.claude/skills/lifeline
```

For one project, shared with the team through the repo:

```sh
git clone https://github.com/reporemaker/lifeline .claude/skills/lifeline
```

## Use

```
/lifeline            # full audit → docs/dependency-report.md
/lifeline map        # context map only
/lifeline deps       # map + external code inventory
/lifeline services   # map + external services
/lifeline vendored   # vendor ledger check only
```

Claude also picks it up on its own when you ask things like *"list this project's dependencies"* or *"is our vendored code still safe?"*. After the report it asks whether you also want a CycloneDX SBOM or a JSON export.

## Why: left-pad

In March 2016 a developer lost a naming dispute over an npm package called `kik` and, in protest, unpublished every package under their account, 273 of them. One was `left-pad`: 11 lines that pad a string on the left.

Thousands of projects depended on it, mostly without knowing, through a dependency of a dependency. Babel and React builds broke worldwide within hours. npm restored the package, which it had never done before, and changed its rules so a package others depend on can no longer simply be removed.

Three lessons, and what lifeline does about each:

| Lesson | lifeline |
|---|---|
| Nobody knew what they depended on | context map, direct and transitive |
| One tiny package can break the whole chain | criticality score per dependency |
| 11 lines are safer in your repo than behind someone else's account | vendoring advisor, plus a ledger so copied code is never forgotten |

## Notes

- **No dependencies of its own.** Plain bash (macOS 3.2 compatible) and standard Unix tools. `curl` is optional.
- **Works offline.** Remote checks are skipped and the report says so. A skipped check is never shown as "current".
- **Static analysis has limits.** Dynamic imports are not traced. Every report ends with a "Limits of This Analysis" section.
- **Reports in your language.** Section names stay the same; the prose follows the language you write in.

## License

[MIT](LICENSE)
