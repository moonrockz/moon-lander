# Design: Split the framework into modules

## Context

See `proposal.md` for the reasons. The current state:

- `pkgs/lander` is one module, `moonrockz/moon-lander`. It holds the root package
  `@lander`, `config` and its subpackages, `formats` and `formats/toml`, `hosting`,
  `hosting/console`, `mediator`, `mediator/async`, and the TypeScript adapters in
  `adapters/node` and `adapters/browser`.
- Its `moon.mod` imports `moonbitlang/async`, `moonbitlang/x`, `unicode-data`, `toml`,
  `yaml`, `ion` and `expect`. MoonBit resolves dependencies by module, so each
  consumer of any package gets all of them.
- Package imports today: `hosting` imports `config`. `mediator` imports nothing.
  `mediator/async` imports `mediator`. `formats` imports `config` and the four
  format packages. `@lander` imports `hosting`.
- `moonrockz/notebooks` and `moonrockz/openrpc` are separate modules in the same
  workspace. They show that the workspace tooling already works with more than one
  published module (`scripts/versions.mbtx`, `scripts/publish.mbtx`,
  `scripts/validate-packages.mbtx`).
- The framework module is not on the publish list (`scripts/publish.mbtx`), so no
  outside consumer exists.
- `add-host-lifecycle` is open. Groups 1, 2 and the native console spike are done.
  Groups 3 to 16 are open (beads lander-4us.5.3 to .16).

## Goals / Non-Goals

**Goals:**

- Each framework module builds and tests on its own targets, as today.
- Each group of `tasks.md` lands as one pull request that keeps `mise run check`
  green.
- `git mv` moves whole files, so `git log --follow` and blame keep the history. For
  code that moves out of part of a file, such as `AppName`, `git blame -C -C` finds
  the history. The repository squash-merges, so a split commit would not survive.
- Source files change only their imports, except for the `AppName` move and the new
  `TimeLimit`.

**Non-Goals:**

- No new public behavior in configuration, mediator or hosting, except the
  `TimeLimit` binding.
- No change to the batteries-included `@lander` entry. Task group 16 of
  `add-host-lifecycle` defines it.

## Decisions

### D1. Five modules with a fixed dependency direction

```text
moonrockz/moon-lander-core          (moonbitlang/core only)
     ↑              ↑            ↑
moon-lander-config  moon-lander-mediator
     ↑                           │
moon-lander-hosting ─────────────┘ (core, config)
     ↑
moonrockz/moon-lander               (all four)
```

Hosting does not import the mediator. The umbrella module `moonrockz/moon-lander`
holds the `@lander` entry and the version. Owner decisions (2026-10-23): core holds
`TimeLimit`; config, mediator and hosting are separate modules; the split comes
before the remaining host-lifecycle groups.

Alternatives:
- One module with more packages. It does not remove the parser dependencies from a
  mediator consumer, because MoonBit resolves dependencies by module.
- Hosting inside `moonrockz/moon-lander`. The owner chose a separate module, so that
  an application can use hosting without the umbrella defaults.
- One module for each package. That gives about fifteen modules to version, publish
  and check, for no new isolation.

### D2. Folders

| Module | Folder | Moved from |
|---|---|---|
| core | `pkgs/core` | new; `AppName` from `pkgs/lander/hosting/names.mbt` |
| config | `pkgs/config` | `pkgs/lander/config/**`, `pkgs/lander/formats/**`, `pkgs/lander/adapters/**` |
| mediator | `pkgs/mediator` | `pkgs/lander/mediator/**` |
| hosting | `pkgs/hosting` | `pkgs/lander/hosting/**` |
| umbrella | `pkgs/lander` | stays: root package, `version.mbt` |

The TypeScript adapters go to `pkgs/config/adapters/node` and
`pkgs/config/adapters/browser`, because only `config/host` and `config/browser` use
them. The AGENTS.md exceptions for these adapters change their paths, not their
rules.

The js signal listeners of the console driver do not go in the config adapter.
Owner decision (2026-10-23), which changes the place in `add-host-lifecycle` O2:
hosting gets its own node adapter, `pkgs/hosting/adapters/node`, with the same rules
(TypeScript over `node:*` only, bundled with the pinned Bun through
`build-node-adapter.mbtx` as a second entry point). Task group 12 of
`add-host-lifecycle` creates it, so this change only records the place. The config
module then has no process-signal code, and the console driver does not depend on
`config/host`.

Alternative: keep O2 as it is. The listeners would be in the public surface of
`moonrockz/moon-lander-config/host`, and hosting would call config for process
signals.

### D3. The main package is the module root

| Package today | Package after the split | Alias in docs |
|---|---|---|
| (new) | `moonrockz/moon-lander-core` | `@lander_core` |
| `moonrockz/moon-lander/config` | `moonrockz/moon-lander-config` | `@config` |
| `moonrockz/moon-lander/config/conventions` | `moonrockz/moon-lander-config/conventions` | `@conventions` |
| `moonrockz/moon-lander/config/host` | `moonrockz/moon-lander-config/host` | `@host` |
| `moonrockz/moon-lander/config/browser` | `moonrockz/moon-lander-config/browser` | `@browser` |
| `moonrockz/moon-lander/config/formats/<name>` | `moonrockz/moon-lander-config/parsers/<name>` | `@toml` and so on |
| `moonrockz/moon-lander/formats` | `moonrockz/moon-lander-config/formats` | `@formats` |
| `moonrockz/moon-lander/formats/toml` | `moonrockz/moon-lander-config/formats/toml` | (override only) |
| `moonrockz/moon-lander/mediator` | `moonrockz/moon-lander-mediator` | `@mediator` |
| `moonrockz/moon-lander/mediator/async` | `moonrockz/moon-lander-mediator/async` | `@mediator_async` |
| `moonrockz/moon-lander/hosting` | `moonrockz/moon-lander-hosting` | `@hosting` |
| `moonrockz/moon-lander/hosting/console` | `moonrockz/moon-lander-hosting/console` | `@console` |
| `moonrockz/moon-lander` | `moonrockz/moon-lander` | `@lander` |

A module name with `-` gives no usable default alias, so every import of a root
package in docs, tests and READMEs gives an explicit alias. The aliases keep the
names that the source uses today, so most source changes are import lines.
`@mediator_async` is explicit because the default alias `@async` hides
`moonbitlang/async`.

Alternative: keep the old subpaths under the new module names, for example
`moonrockz/moon-lander-config/config`. That is a smaller edit, but every import says
the name two times, and the names stay longer for the life of the framework.

### D4. Parsers move to `parsers/<name>`

With the configuration core at the module root, `config/formats/toml` (the TOML
parser) and `formats/toml` (the TOML-only implementation of the virtual package)
would get the same path. The parsers move to `parsers/<name>`. The virtual package
and its implementation keep `formats` and `formats/toml`, because applications write
these paths in `overrides`, and the `configuration-core` spec names them.

Alternative: rename the virtual package, for example to `linked`. Applications use
the virtual package more often than a parser package, so its name stays.

### D5. `AppName` moves to core with a typed rule

`AppName`, its `Show`, `Eq`, `Hash` and `Debug` and its tests move to the core root
package with no change to the rules. The parse raises a new core error:

```moonbit
pub suberror AppNameError {
  InvalidAppName(text~ : String, rule~ : AppNameRule)
}

pub enum AppNameRule {
  Empty
  FirstNotAsciiLetter
  CharNotAllowed(Char)
}
```

`pub suberror` and `pub enum` let callers match the cases but not make them. The
`message` text stays the same as today. `HostError` loses `InvalidAppName`. The host
builder and `@lander.cli` take `@lander_core.AppName`. The umbrella re-exports
`AppName`, `AppNameError` and `AppNameRule` from `@lander`, as `add-host-lifecycle`
design D15 expects for the host types.

The new error must exist, because a core type cannot raise `HostError`. The rule enum
costs nothing more at this point, and it closes part of finding 2 of lander-4us.25.
The other `AppName` findings of lander-4us.25 (device names, length) stay there.

### D6. `TimeLimit`

```moonbit
pub struct TimeLimit { priv millis : Int } derive(Eq, Compare, Hash, Debug)

pub fn TimeLimit::millis(count : Int) -> TimeLimit raise TimeLimitError
pub fn TimeLimit::seconds(count : Int) -> TimeLimit raise TimeLimitError
pub fn TimeLimit::parse(text : String) -> TimeLimit raise TimeLimitError
pub fn TimeLimit::to_millis(self : TimeLimit) -> Int
pub impl Show for TimeLimit   // canonical text, for example "2m30s"

pub suberror TimeLimitError {
  InvalidTimeLimit(input~ : String, rule~ : TimeLimitRule)
}

pub enum TimeLimitRule {
  Empty
  UnexpectedSpace
  NotANumber
  MissingUnit
  UnknownUnit(String)
  UnitsOutOfOrder
  RepeatedUnit
  NotWholeMilliseconds
  NotPositive
  AboveLargest
}
```

- The range is 1 to `Int` max milliseconds, the range of `@aio.with_timeout`. So
  `to_millis` cannot fail, and `Int` is enough for the field.
- `seconds` multiplies in `Int64`, so a large count gives `AboveLargest` and not an
  overflow.
- For a code constructor, `input` is the count with its unit, for example `-1ms`.
- Grammar: a part is a number, at most one space, and a unit. A number is ASCII
  digits, with an optional `.` and one or more digits after it (`.5` and `5.` are
  `NotANumber`). A unit is the longest run of ASCII letters after the number. The
  units are `ms`, `millisecond`, `milliseconds`, `s`, `second`, `seconds`, `m`,
  `minute`, `minutes`, `h`, `hour` and `hours`. They are lower case only, and the
  singular and plural forms are the same unit. At most one space goes between parts,
  and none at the start or the end.
- The sum uses exact decimal arithmetic (`moonbitlang/core/bigint`, part of core), so
  a long fraction or a large number gives `NotWholeMilliseconds` or `AboveLargest`,
  and never an overflow or a rounding.
- A check order gives one rule for each input: the shape rules first (`Empty`,
  `UnexpectedSpace`, `NotANumber`, `MissingUnit`, `UnknownUnit`), then the order rules
  (`UnitsOutOfOrder`, `RepeatedUnit`), then the value rules (`NotWholeMilliseconds`,
  `NotPositive`, `AboveLargest`).
- No `d` unit, because one day is close to the largest limit. No ISO 8601 text.
- The name is `TimeLimit` and not `Duration`, so that it does not look like
  `@time.Duration` of `moonbitlang/x`. That type allows negative values and raises
  untyped errors. The owner can rename the type before group 2 lands.

### D7. The `TimeLimit` binding lives in config

`impl FromConfig for @lander_core.TimeLimit` goes in the configuration core root
package, beside the impls for `String`, `Int` and the Ion types. MoonBit allows an
impl only in the package of the trait or of the type, and core cannot import config.
The impl accepts text and a symbol with text, like the `String` impl. A parse failure
becomes a decode failure for the key, with the `TimeLimitError` message as its detail
and the usual blame.

### D8. A check for the dependency direction

`scripts/validate-packages.mbtx` gets a table of the allowed framework imports from
D1. For each framework member it reads the `import` block of `moon.mod` with line
matching, as the UI check does, and fails with both module names for an import that
is not in the table. For core it also fails for any import at all. So the core tests
use only `moonbitlang/core` (`inspect`, `assert_eq`, `@debug`) and not
`moonrockz/expect`, because a test import in `moon.mod` is also a dependency of each
consumer.

### D9. One version, as today

`scripts/versions.mbtx` already sets the `version` of each `moon.work` member and
each sibling import `"<module>@X.Y.Z"`. The new modules import each other with the
root version, so the script needs no new rule. A test fixture with two sibling
modules shows this. `version_files` stays `pkgs/lander/version.mbt`.

### D10. Scripts, checks and the docs site

| Script or file | Change |
|---|---|
| `check-config.mbtx` | Package paths under `pkgs/config` |
| `check-mediator.mbtx` | Package paths under `pkgs/mediator` |
| `check-console.mbtx` | Group 1 makes it copy a list of modules (core and `pkgs/lander`), because `pkgs/lander` then imports core. Group 6 sets the list to `pkgs/core`, `pkgs/config` and `pkgs/hosting`; the consumer imports `moonrockz/moon-lander-hosting` |
| `check-formats-registry.mbtx` | Group 1 makes it package and serve a list of candidate modules (core and `pkgs/lander`). Group 3 sets the list to `pkgs/core` and `pkgs/config`; the consumer imports `moonrockz/moon-lander-config` |
| `build-node-adapter.mbtx`, `build-browser-adapter.mbtx`, `test-node-adapter.mbtx` | Adapter and generated-file paths under `pkgs/config` |
| `validate-packages.mbtx` | D8 |
| `publish.mbtx` | List unchanged. Its comment gives the order for the first framework release: core, config, mediator, hosting, umbrella |
| `site/site.json` | `api` lists `pkgs/core`, `pkgs/config`, `pkgs/mediator`, `pkgs/hosting` and `pkgs/lander` |
| `site/site.json` `packages` | Lists `core`, `config`, `mediator` and `hosting` beside `lander`. The guide pages move, for example `/docs/packages/lander/config/` becomes `/docs/packages/config/` (call: no spec names these URLs, and the guide must follow the modules) |
| `CHANGELOG.md` | No entry in this change. `CONTRIBUTING.md` gives the `## X.Y.Z` section to the release pull request, so the first framework release notes the new paths (call). Old paths in its history stay |
| `.github/workflows/*.yml`, `.config/mise/config.toml` | Path filters and descriptions that name `pkgs/lander` |

The release gate lander-4us.9 then uses `check:formats-registry` for two modules.

### D11. Order of the groups

1. Core with `AppName` (`pkgs/lander` imports the new module).
2. `TimeLimit` in core.
3. Config moves to `moonrockz/moon-lander-config`.
4. The `TimeLimit` binding.
5. Mediator moves to `moonrockz/moon-lander-mediator`.
6. Hosting moves to `moonrockz/moon-lander-hosting`. The `add-host-lifecycle`
   artifacts get the new paths.
7. The dependency check, the docs and the archive of this change.

Groups 2 and 5 do not depend on group 3, so they can go in parallel with it.
`add-host-lifecycle` group 3 (lander-4us.5.3) waits for group 6.

### D12. Edits to `add-host-lifecycle`

Group 1 changes the `AppName` scenario of its spec delta (`HostError::InvalidAppName`
becomes `AppNameError::InvalidAppName` with a rule). Group 6 changes the package
paths in its proposal, design and tasks: `moonrockz/moon-lander/hosting` becomes
`moonrockz/moon-lander-hosting`, `hosting/argparse` and `hosting/console` follow, and
task 16.1 names `moonrockz/moon-lander-config/formats`. Design D7 (O2) and task
12.1 put the js signal listeners in `pkgs/hosting/adapters/node` (D2), and the
AGENTS.md exception for the node adapter names both adapters. Ticked tasks keep their
ticks. Their text gets the new paths, so they still agree with the code.

## Risks / Trade-offs

- [A root package import of a module with `-` in its name fails] → Low. It works
  today: `pkgs/lander/moon.pkg` and `tests` import `moonrockz/moon-lander` as
  `@lander`. Task 1.2 checks it again for core.
- [A virtual package override across a module boundary fails] → Low. It works today:
  the `tests` module overrides `moonrockz/moon-lander/formats/toml`. `check:formats`
  and `check:formats-registry` run in group 3 against the new paths.
- [`pkg.generated.mbti` files move, and lint sees them as new] → Each group stages
  the moved interface files with the move.
- [CI takes longer with more modules] → The checks run the same packages as today;
  only the module count changes. Measure in group 7.
- [Open branches that touch `pkgs/lander` get conflicts] → Land the groups soon, one
  after another, before the lifecycle work starts again.
- [A doc example keeps an old path] → README examples are doc tests (`mbt check`),
  so an old path fails the build. `api:` links in the site fail the build for an
  unknown package.

## Migration Plan

No outside consumer exists, so no consumer migration is needed. In this repository,
each group moves its packages and changes every import in the same pull request.
Rollback is a revert of the group's pull request.

## Open Questions

- The docs aliases `@lander_core` and `@mediator_async` can change in review without
  a change to the specs.
