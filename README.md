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

## Why

While you build a project you pull in libraries, forks and ready-made snippets. Then the project ships, and from that day on every problem in the borrowed code is your problem: a security hole, a package that disappears, a maintainer who walks away or hands the keys to a stranger.

lifeline finds the dead, broken and ownerless code your project rests on: packages nobody maintains anymore, packages whose maintainer changed, packages whose maintainer nobody can name. Then it helps you act on them: replace one with a built-in, copy in only the part you use, or keep it and watch it.

**Run it regularly.** Dependencies change after you stop looking. A package that was healthy on delivery day can be abandoned, handed over or compromised a year later, and nothing in your repo changes when that happens. Run lifeline before every release and on a schedule, monthly for example. Each report has a section on what changed since the last one.

## Two stories

**left-pad, 2016.** A developer lost a naming dispute with a company over an npm package and, in protest, removed every package on their account, 273 of them. One was `left-pad`, 11 lines that pad a string on the left. Thousands of projects depended on it without knowing, through a dependency of a dependency. Babel and React builds broke worldwide within hours. npm restored the package, which it had never done before, and changed its rules so a package others depend on can no longer simply be removed.

**xz Utils, 2024.** `xz` is a compression library found in nearly every Linux system, kept for years by one volunteer. In 2021 a contributor calling themselves "Jia Tan" started sending helpful patches. Over two years, while other accounts publicly pressured the tired maintainer to hand over the work, Jia Tan earned trust and the right to publish releases. In February 2024 versions 5.6.0 and 5.6.1 shipped with a backdoor hidden in test files and the build script, built to let an attacker into servers through SSH. It was found by chance a month later, when Andres Freund, an engineer at Microsoft, chased a half-second delay in SSH logins. By then it was already in test versions of Fedora, Debian and other distributions, weeks away from millions of servers ([CVE-2024-3094](https://nvd.nist.gov/vuln/detail/CVE-2024-3094), severity 10 out of 10). The same thing had happened before on npm: in 2018 the tired maintainer of `event-stream`, with about two million downloads a week, handed it to a volunteer who added a dependency that stole from a Bitcoin wallet app.

lifeline would not have found the xz backdoor; no tool did. What it does is show you, before something like that happens, which of your dependencies rest on one tired person, haven't had a release in years, or have just changed hands.

## What it does

- **Maps** every outside dependency: packages (declared and actually imported), CI actions, Docker images, CDN assets, external services.
- **Checks upstream health:** last release, deprecation, archived repository, number of maintainers, install-time scripts.
- **Measures the real cost** of a package: total lines, lines actually reachable, how many other packages it pulls in, which of its functions you call.
- **Points to built-ins first:** `left-pad` → `padStart`, `rimraf` → `fs.rm`. Deleting a dependency beats copying it.
- **Vendors only what you use**, after a mandatory license gate (copyleft is never recommended), and only with your approval.
- **Tracks vendored code** in a `VENDORED.md` ledger: upstream updates, known CVEs ([osv.dev](https://osv.dev)), and a checksum that catches any change to the copy.
- **Helps patch it:** when upstream fixes something, it diffs the old and new version against your copy and proposes the patch.

It audits, measures and advises. It changes your project only when you say yes.

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
/lifeline            # full audit
/lifeline map        # context map only
/lifeline deps       # map + external code inventory
/lifeline services   # map + external services
/lifeline vendored   # vendor ledger check only
```

Reports go to a `LifeLine_Report/` folder at the project root (`dependency-report.md`, plus an SBOM or JSON export if you ask for one). Claude also picks the skill up on its own when you ask things like *"list this project's dependencies"* or *"is our vendored code still safe?"*.

## Notes

- **No dependencies of its own.** Plain bash (macOS 3.2 compatible) and standard Unix tools. `curl`, `node` and `python3` make it see more, but are optional.
- **Works offline.** Remote checks are skipped and the report says so. A skipped check is never shown as "current".
- **Static analysis has limits.** Dynamic imports are not traced, and "reachable lines" are counted per file. Every report ends with a "Limits of This Analysis" section.
- **Reports in your language.** Section names and file names stay English; the prose follows the language you write in.

## License

[MIT](LICENSE)
