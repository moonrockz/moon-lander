# Tasks

Epic: lander-4us.40

Each group is one pull request. Run `mise run check` after each group, and run
`mise run format` before each commit. Move files with `git mv`. Stage the moved and
new `pkg.generated.mbti` files that lint writes. Group 1 comes first. Groups 2 and 5
can go in parallel with group 3. Group 4 needs groups 2 and 3. Group 6 needs group 3.
Group 7 needs all others and archives the change. The groups of `add-host-lifecycle`
from lander-4us.5.3 on wait for group 6.

## 1. Core module with the application name

Bead: lander-4us.40.1

- [ ] 1.1 Create `pkgs/core` with `moon.mod` (`moonrockz/moon-lander-core`, root version, no imports, `readme = "README.mbt.md"`) and a root `moon.pkg`; add `./pkgs/core` to `moon.work`; verify that `mise run validate` and `mise run validate:versions` pass and that `moon check --target all` builds the empty module
- [ ] 1.2 Verify that `pkgs/lander` can import the core root package with the explicit alias `@lander_core` on wasm, wasm-gc, js and native (design D3 risk), and record the result in the bead
- [ ] 1.3 Move `AppName`, its trait impls and its tests from `pkgs/lander/hosting/names.mbt` to core with `git mv` or a split commit; add `AppNameError` and `AppNameRule` (design D5); remove `InvalidAppName` from `HostError`; verify each `AppName` rule on both sides of its limit with `inspect` and `assert_eq` only, and that each rule gives its own `AppNameRule` case
- [ ] 1.4 Make `@hosting.builder`, `@lander.cli` and the hosting tests take `@lander_core.AppName`, and re-export it as `@lander.AppName`; verify `mise run test` on all four targets and the native and js `@hosting.run` tests
- [ ] 1.5 Change the `AppName` scenario in `openspec/changes/add-host-lifecycle/specs/host-lifecycle/spec.md` (`HostError::InvalidAppName` becomes `AppNameError::InvalidAppName` with a rule) and the `AppName` rows in its design; verify `mise exec -- openspec validate --all --strict`
- [ ] 1.6 Write `pkgs/core/README.mbt.md` with a doc-test example that parses an application name and matches a failure by its rule; verify that `mise run test` compiles and runs it on all four targets

## 2. Time limit in core

Bead: lander-4us.40.2

- [ ] 2.1 Add `TimeLimit`, `TimeLimitError` and `TimeLimitRule` (design D6) with `millis`, `seconds`, `to_millis`, `Eq`, `Compare`, `Hash` and `Debug`; verify the "Time limit range" and "Time limit constructors" scenarios on all four targets, with values on each side of 1 and of the largest limit
- [ ] 2.2 Add `TimeLimit::parse` with the grammar of design D6; verify every scenario of "Time limit text form" and "Time limit text errors" on all four targets, and that each rule gives its own `TimeLimitRule` case
- [ ] 2.3 Add `Show` with the canonical text; verify the "Canonical text" scenario, and a `moonbitlang/core/quickcheck` property that parse of the text of any valid limit gives an equal limit (the property uses only `moonbitlang/core`)
- [ ] 2.4 Add a `TimeLimit` section to `pkgs/core/README.mbt.md` with a doc-test example that parses `2m30s` and passes `to_millis()` to a function that takes `Int`; verify that `mise run test` runs it

## 3. Configuration module

Bead: lander-4us.40.3

- [ ] 3.1 Create `pkgs/config` (`moonrockz/moon-lander-config`) with the third-party imports that config needs and an import of core; move `pkgs/lander/config` to the module root, `config/conventions`, `config/host` and `config/browser` below it, `config/formats/<name>` to `parsers/<name>`, `pkgs/lander/formats` and `formats/toml` to `formats` and `formats/toml`, and `pkgs/lander/adapters` to `pkgs/config/adapters` (design D2 to D4); verify that `moon check --target all` builds the module
- [ ] 3.2 Change every import of the moved packages in `pkgs/lander`, `tests/` and the package READMEs to the new paths and the aliases of design D3; remove the config imports from `pkgs/lander/moon.mod`; verify `mise run test` on all four targets
- [ ] 3.3 Change `build-node-adapter.mbtx`, `test-node-adapter.mbtx`, `build-browser-adapter.mbtx` and `check-config.mbtx` to the new paths, and update their own tests; verify `mise run check:node-adapter`, `mise run check:browser-adapter`, `mise run check:browser-fixture` and `mise run check:config`
- [ ] 3.4 Change `check-formats-registry.mbtx` to package `pkgs/core` and `pkgs/config` and to serve both archives from the loopback registry, with a consumer that imports `moonrockz/moon-lander-config` (also in its `--published` mode for the release gate lander-4us.9); verify `mise run check:formats` and `mise run check:formats-registry` on all four targets, and the scenarios of the `configuration-core` delta with the new override path
- [ ] 3.5 Change the paths in the AGENTS.md adapter exceptions and in `.config/mise/config.toml`; verify that `mise run check` passes

## 4. Time limit binding

Bead: lander-4us.40.4

- [ ] 4.1 Add `impl FromConfig for @lander_core.TimeLimit` in the configuration core (design D7); verify the four scenarios of "Bind a time limit" on all four targets, with a decode error that names the rule and blames the source
- [ ] 4.2 Add a time-limit example to the binding section of `pkgs/config/README.mbt.md`; verify that `mise run test` runs it

## 5. Mediator module

Bead: lander-4us.40.5

- [ ] 5.1 Create `pkgs/mediator` (`moonrockz/moon-lander-mediator`) with imports of core and `moonbitlang/async` only, and with no TOML, YAML, JSON5 or Ion module; move `pkgs/lander/mediator` to the module root and `mediator/async` to `async`; keep the `supported_targets` of `async` and add a comment that gives the reason for no `wasm-gc`; verify that `moon check` builds the module on its targets
- [ ] 5.2 Change the imports in `tests/mediator-acceptance`, `tests/mediator-async-acceptance`, the READMEs and `check-mediator.mbtx`; verify `mise run check:mediator` for each target and `mise run test`
- [ ] 5.3 Verify the "Mediator without configuration parsers" scenario with a consumer outside the workspace that imports only the mediator module by path, and record its resolved dependencies in the bead

## 6. Hosting module

Bead: lander-4us.40.6

- [ ] 6.1 Create `pkgs/hosting` (`moonrockz/moon-lander-hosting`) with imports of core, config, `moonbitlang/async` and `unicode-data`; move `pkgs/lander/hosting` to the module root and `hosting/console` (with `signal_stub.c`) to `console`; verify that `moon check` builds the module on its targets and `moon test --target native` runs the console tests
- [ ] 6.2 Change the imports in `pkgs/lander`, `tests/console-signal-acceptance` and the READMEs, and leave `pkgs/lander/moon.mod` with imports of the four framework modules and `moonbitlang/async`; verify `mise run test` on all four targets
- [ ] 6.3 Change `check-console.mbtx` to copy `pkgs/core`, `pkgs/config` and `pkgs/hosting` into the isolated workspace, with a consumer that imports `moonrockz/moon-lander-hosting`; verify `mise run check:console` on Linux and macOS and with `mise run test:native-zig`
- [ ] 6.4 Change the package paths in the proposal, design and tasks of `add-host-lifecycle`, move the js signal listeners of O2 and task 12.1 to `pkgs/hosting/adapters/node` (design D2 and D12), and change the AGENTS.md exceptions for the console stub and the node adapter; verify `mise exec -- openspec validate --all --strict` and that no file outside `openspec/changes/archive/` and the released sections of `CHANGELOG.md` names `moonrockz/moon-lander/hosting`

## 7. Dependency check, docs and archive

Bead: lander-4us.40.7

- [ ] 7.1 Add the dependency-direction check of design D8 to `validate-packages.mbtx`, with script tests for an allowed import, an import against the direction and a core import; verify the "Import against the direction" and "Core imports a third-party module" scenarios and that `mise run validate` passes on the real workspace
- [ ] 7.2 Add a test fixture to `versions.mbtx` with two sibling framework modules; verify the "Version drift" and "Set the version" scenarios
- [ ] 7.3 Change `site/site.json` (`api` lists the five framework folders, and `packages` adds `core`, `config`, `mediator` and `hosting`), `publish.mbtx` (the comment with the release order), the path filters in `.github/workflows/`, `README.md` and `docs/design/overview.md`; verify that `mise run build:site` passes, that the "API package index" scenario holds, that the config and mediator guide pages exist at their new URLs, and that `api:` links to old paths fail the build
- [ ] 7.4 Change the "Publishing" section of AGENTS.md to name the five framework modules; verify that no file outside `openspec/changes/archive/` and the released sections of `CHANGELOG.md` names a `moonrockz/moon-lander/<package>` path
- [ ] 7.5 Measure the CI time of `mise run check` before and after the split, and record it in the bead
- [ ] 7.6 Archive this change with `openspec archive split-framework-modules` in the same pull request; verify `mise exec -- openspec validate --all --strict`

## Workflow follow-up

- After the merge of group 7, close the beads with the pull request and merge SHA,
  close the epic, and sync, as "Land a change" in `CONTRIBUTING.md` says.
- Unblock lander-4us.5.3, and make lander-4us.23, .24 and 5.10 use `TimeLimit`.
