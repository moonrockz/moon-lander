# Proposal: Split the framework into modules

## Why

The framework is one module, `moonrockz/moon-lander`. A program that uses only the
mediator gets the TOML, YAML, JSON5 and Ion parsers as dependencies, although the
mediator imports none of them. The packages also cannot share a domain type in the
correct direction: `hosting` imports `config`, so `config/conventions` cannot use
`AppName` from `hosting`. And no package can hold the time-limit type that the
mediator timeout and the hosting shutdown timeout both need (audit lander-4us.21).

Do the split now. The framework module is not published yet, so no user must change
an import. The remaining groups of `add-host-lifecycle` (5.3 to 5.16) then land in
the new modules and do not move again.

## What Changes

- **BREAKING** Split `moonrockz/moon-lander` (`pkgs/lander`) into five modules. All
  five share the root version:

  | Module | Folder | Holds | Imports from the framework |
  |---|---|---|---|
  | `moonrockz/moon-lander-core` | `pkgs/core` | `AppName`, `TimeLimit` | none |
  | `moonrockz/moon-lander-config` | `pkgs/config` | configuration core, formats, conventions, host, browser | core |
  | `moonrockz/moon-lander-mediator` | `pkgs/mediator` | mediator, async mediator | core |
  | `moonrockz/moon-lander-hosting` | `pkgs/hosting` | host lifecycle, console driver | core, config |
  | `moonrockz/moon-lander` | `pkgs/lander` | `@lander` entry, version | all four |

- **BREAKING** Change the package paths. The main package of each module is its
  root package, for example `moonrockz/moon-lander-config` for the configuration
  core and `moonrockz/moon-lander-config/conventions` for conventions. The format
  parsers move to `parsers/<name>`, so the virtual package `formats` and its TOML-only
  implementation `formats/toml` keep their short paths.
- **BREAKING** Move `AppName` from `hosting` to core. Its parse failure becomes the
  core error `AppNameError`, which names the input and the broken rule as an enum.
  `HostError` loses `InvalidAppName`.
- Add `TimeLimit` to core: a positive amount of time, not more than the `Int`
  milliseconds that `moonbitlang/async` takes. It has constructors from milliseconds
  and seconds, and a parse of text such as `9ms`, `10 seconds`, `1.5s` and `2m30s`.
- Add a configuration binding for `TimeLimit`, so an application can bind its own
  timeouts from configuration text.
- Add a workspace check that fails when a module imports a framework module against
  the dependency direction in the table.
- Update the scripts, CI checks, docs site, READMEs and `AGENTS.md` for the new
  paths. Update the artifacts of `add-host-lifecycle` for the new hosting paths and
  the `AppName` location.

## Capabilities

### New Capabilities

- `framework-modules`: the module set, the folders, the root-package paths, the
  dependency direction and its check, and one version for all framework modules.
- `time-limits`: the `TimeLimit` type, its rules, its constructors, its text form and
  its typed parse errors.

### Modified Capabilities

- `configuration-core`: the linked format set and the TOML-only implementation get
  the paths `moonrockz/moon-lander-config/formats` and
  `moonrockz/moon-lander-config/formats/toml`.
- `configuration-binding`: add the binding of a `TimeLimit` from configuration text.
- `docs-site`: the API index lists the new framework modules.

## Out of scope

- No publication. The framework modules stay off the publish list until the release
  gate lander-4us.9 and the release policy (no release before the host lifecycle
  lands) allow it. The design records the publish order for that time.
- No `EnvPrefix`. Task 7.7 of `add-host-lifecycle` adds it, in core.
- No use of `TimeLimit` by the mediator or the host. Fix beads lander-4us.23 and .24
  and task 10.3 of `add-host-lifecycle` do that.
- No other fix from the domain-type audit. The fix beads lander-4us.23 to .39 stay
  open. One exception: the new `AppNameError` names its rule as an enum.
- No host reading of a shutdown timeout from configuration. That stays a non-goal of
  `add-host-lifecycle`.
- No ISO 8601 text (`PT30S`) for `TimeLimit`.
- No change to `moonrockz/notebooks` or `moonrockz/openrpc`.

## Impact

- Code: all packages under `pkgs/lander` move. Source files change only their
  imports, except `AppName`, `HostError` and the new `TimeLimit`.
- Public API: every framework import path changes. The module is not published, so
  only this repository's tests and docs are consumers.
- Workspace: `moon.work`, five `moon.mod` files, `scripts/versions.mbtx`,
  `scripts/validate-packages.mbtx`, and the check and build scripts that name
  `pkgs/lander` (`check-config`, `check-mediator`, `check-console`,
  `check-formats-registry`, `build-node-adapter`, `build-browser-adapter`).
- Tests: every suite under `tests/` that imports the framework changes its imports.
  The isolated checks (`check:console`, `check:formats-registry`) must copy or serve
  more than one module.
- Docs: `site/site.json`, package READMEs, `README.md`, `AGENTS.md`,
  and `docs/design/overview.md`. `CHANGELOG.md` gets its entry in the first release pull request.
- Tracker: the open groups of `add-host-lifecycle` wait for the hosting move. The
  fix beads lander-4us.23, .24, .25, .27 and .29 and task 10.3 of
  `add-host-lifecycle` then use core.
