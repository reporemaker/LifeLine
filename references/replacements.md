# Native Replacements Reference

Packages whose job the language or runtime now does on its own. For these, the best
answer to "vendor it?" is usually neither vendor nor keep: **delete the dependency and
use the built-in**. No license baggage, no ledger entry, nothing left to watch.

How to use (Step 3):

1. Match every direct dependency, and every vendored entry, against the tables below.
2. Check the **minimum runtime** against the project's real target (`engines` in
   package.json, `browserslist`, `requires-python`, the CI Node/Python version). A
   replacement the target does not support is not a replacement.
3. Check the **semantics note**. Some built-ins are close but not identical; say so.
4. Report it as a 🟡 finding: *"`left-pad` → `String.prototype.padStart` (ES2017)"*,
   listed before any vendoring suggestion for the same package.
5. Never rewrite call sites on your own - this is a recommendation like any other.

The tables are a starting point, not a complete list. A package not listed here can
still be replaceable; judge it from `used-api.sh` (what is actually called) and say
that the match was made by hand.

## JavaScript / TypeScript

| Package(s) | Built-in | Minimum runtime | Semantics note |
|---|---|---|---|
| `left-pad`, `pad-left`, `string.prototype.padstart` | `str.padStart(len, ch)` | ES2017 · Node 8 | - |
| `right-pad`, `pad-right`, `string.prototype.padend` | `str.padEnd(len, ch)` | ES2017 · Node 8 | - |
| `is-array`, `isarray` | `Array.isArray(x)` | ES5 | - |
| `array-includes`, `array.prototype.includes` | `arr.includes(x)` | ES2016 · Node 6 | finds `NaN`, unlike `indexOf` |
| `array-flatten`, `array.prototype.flat` | `arr.flat(depth)` | ES2019 · Node 11 | `flat(Infinity)` for deep |
| `array-uniq`, `array-unique`, `uniq` | `[...new Set(arr)]` | ES2015 | identity equality only |
| `object-assign` | `Object.assign(t, ...s)` | ES2015 · Node 4 | - |
| `object.entries`, `object.values`, `object-values` | `Object.entries` / `Object.values` | ES2017 · Node 7 | - |
| `object.fromentries` | `Object.fromEntries(it)` | ES2019 · Node 12 | - |
| `string.prototype.trimstart`, `trim-left` (and `-end`/`-right`) | `str.trimStart()` / `str.trimEnd()` | ES2019 · Node 10 | - |
| `is-nan` | `Number.isNaN(x)` | ES2015 | no coercion, unlike global `isNaN` |
| `is-integer`, `number-is-integer` | `Number.isInteger(x)` | ES2015 | - |
| `is-finite`, `number-is-finite` | `Number.isFinite(x)` | ES2015 | no coercion |
| `es6-promise`, `promise-polyfill`, `native-promise-only` | `Promise` | ES2015 · Node 4 | - |
| `node-fetch`, `cross-fetch`, `isomorphic-fetch`, `whatwg-fetch` | global `fetch` | Node 18 (stable from 21) · current browsers | streams and agent options differ from node-fetch |
| `abort-controller` | global `AbortController` | Node 15 | - |
| `uuid` (only `v4`) | `crypto.randomUUID()` | Node 14.17 (global `crypto` from Node 19) · browsers in secure contexts | v4 only; keep `uuid` for v1/v5/v7 or `validate` |
| `lodash.get`, `dlv`, `object-path` (reads only) | optional chaining `a?.b?.c ?? def` | ES2020 · Node 14 | static paths only; a path held in a string still needs a helper |
| `lodash.clonedeep`, `clone-deep` | `structuredClone(x)` | Node 17 · current browsers | throws on functions; class instances come back as plain objects |
| `lodash.isequal`, `deep-equal` (Node only) | `util.isDeepStrictEqual(a, b)` | Node 9 | Node only, not browsers |
| `querystring` (npm package), `qs` (flat use only) | `URLSearchParams` | Node 10 · browsers | no nested objects - keep `qs` if nesting is used |
| `url-parse` | `new URL(str, base)` | Node 10 · browsers | throws on invalid input instead of returning partial |
| `rimraf` | `fs.rm(p, { recursive: true, force: true })` | Node 14.14 | no glob support (rimraf 4+ globs only with `--glob`) |
| `mkdirp` | `fs.mkdir(p, { recursive: true })` | Node 10.12 | - |
| `strip-ansi` | `util.stripVTControlCharacters(s)` | Node 16.11 | Node only |
| `inherits`, `util.inherits` use | `class B extends A` | ES2015 | - |
| `has`, `has-own-prop` | `Object.hasOwn(o, k)` | ES2022 · Node 16.9 | - |
| `array.prototype.findlast` | `arr.findLast(fn)` | ES2023 · Node 18 | - |
| `string.prototype.replaceall` | `str.replaceAll(a, b)` | ES2021 · Node 15 | - |
| `globalthis` | `globalThis` | ES2020 · Node 12 | - |
| `dotenv` (load-only use) | `node --env-file=.env` / `process.loadEnvFile()` | Node 20.6 / 21.7 | no variable expansion; keep `dotenv` if `dotenv-expand` features are used |

## Python

| Package | Built-in | Minimum runtime | Semantics note |
|---|---|---|---|
| `six` | plain Python 3 | 3.0 | remove `six.` calls; mechanical |
| `mock` | `unittest.mock` | 3.3 | - |
| `futures` | `concurrent.futures` | 3.2 | - |
| `enum34` | `enum` | 3.4 | installing `enum34` on 3.x breaks `enum` - remove it |
| `pathlib2` | `pathlib` | 3.4 | - |
| `typing` (PyPI backport) | `typing` | 3.5 | the backport shadows the stdlib - remove it |
| `dataclasses` (backport) | `dataclasses` | 3.7 | - |
| `importlib-metadata` | `importlib.metadata` | 3.8 (full API 3.10) | - |
| `importlib-resources` | `importlib.resources` | 3.9 (`files()` API) | - |
| `toml` (read only) | `tomllib` | 3.11 | read only; keep a package for writing |
| `contextlib2` | `contextlib` | 3.7 | - |
| `backports.zoneinfo`, `pytz` (new code) | `zoneinfo` | 3.9 | `pytz` uses `localize()`; not a drop-in, a migration |
| `subprocess32` | `subprocess` | 3.2 | - |
| `ipaddress` (backport) | `ipaddress` | 3.3 | - |
