# Tasks

Epic: lander-4us.3

Each group is one story with its own bead.
Start a group only after `add-configuration-core` gives the types that the group uses
(`FileTree`, `FileRequest`, `LoadStep`, `FileRole`, `ConfigError` variants, `exclude`,
the format registry and the builder entry for discovery).
Run `mise run format` and `mise run check` before each group is closed.

## 1. Tracer bullet: one root file found by walk-up and loaded

Bead: lander-4us.3.1

- [x] 1.1 Create the package `pkgs/lander/config/conventions` for all four targets with a dependency on `@config` only, and verify `mise run build` passes.
- [x] 1.2 Add `DiscoveryOptions` and `base(name, prefix?, display?)` over the core `FileTree`, using the core `@config.Platform` (core design D4a), and verify a unit test that builds a complete tree and reads one listing.
- [x] 1.3 Add the `<app>.<ext>` layout with extensions from the registered formats and walk-up with no boundary, and verify the "Configuration found from a nested directory" scenario as a test.
- [x] 1.4 Add `@conventions.add` so that the core `@config.load(builder, tree)` runs discovery, return ordered `ConfigSource` values with role `Workspace` and priority 300, and verify a test that reads `project.name` from the merged result on wasm, wasm-gc, js and native.
- [x] 1.5 Add a package README with a runnable example of 1.3 and 1.4 that uses `|> @conventions.add(@conventions.app_dirs("acme"))`, and verify `mise run test` runs the example.

## 2. Candidate layouts, extensions, ambiguity and legacy fallback

Bead: lander-4us.3.2

- [ ] 2.1 Add the `.<app>/<app>.<ext>` and `.config/<app>/config.<ext>` layouts with exact-name matching through listings, and verify the three "Candidate layouts per location" scenarios.
- [ ] 2.2 Derive the searched extensions from the registered formats and keep their order only for reports, and verify the two "Searched extensions come from registered formats" scenarios.
- [ ] 2.3 Raise the core `ConfigError::Ambiguous(display~, location~, candidates~)` with the display name of the convention set, and verify the "Ambiguity at one location is an error" scenarios and the "Ambiguity in the nearest directory stops discovery" scenario.
- [ ] 2.4 Add `legacy(name, format~, decode~)` as a root marker and fallback whose format does not join the searched extensions, and verify the two "Legacy fallback candidate" scenarios.

## 3. Stop boundary and isolated mode

Bead: lander-4us.3.3

- [ ] 3.1 Add `boundary(dir)` and make the walk-up inclusive of the boundary, and verify the three "Explicit stop boundary" scenarios, including `ConfigError::OutsideBoundary`.
- [ ] 3.2 Read isolated mode from `DiscoveryOptions` and set system, global, local-override and user-override selections to `Skip` with skipped reports, and verify the two "Isolated mode" scenarios.
- [ ] 3.3 Document the boundary and isolated mode in the package README with a test-root example, and verify the example runs.

## 4. System, global user and application-home directories on every platform

Bead: lander-4us.3.4

- [ ] 4.1 Add `system_dir` for Linux, macOS and Windows (`PROGRAMDATA` with the `C:/ProgramData` fallback), and verify the two "System directory" scenarios.
- [ ] 4.2 Add `user_config_dir` with the absolute-only XDG rule, the macOS directory and `APPDATA` on Windows, and verify the four "Global user configuration directory" scenarios.
- [ ] 4.3 Add `app_home` with `$<PREFIX>_HOME`, `USERPROFILE` on Windows and the empty-means-unset rule, and verify the four "Application home directory" scenarios.
- [ ] 4.4 Treat all global candidates as one source and report every candidate, and verify the "Two global files" and "Not-found global source lists candidates" scenarios.
- [ ] 4.5 Add the `/`-form path value with drive and UNC absolute checks and `\` to `/` conversion of path-valued variables on Windows, and verify the "Path handling on Windows" scenarios with tests that give `Platform::Windows` on every target.
- [ ] 4.6 Add `app_dirs(name, prefix?, display?)` as `base` plus the standard parts, and `without(part)`, and verify a test that removes the system part.
- [ ] 4.7 Read every directory variable only from the `env_vars` set of the core load context, never from the process, and verify the "Directories come only from the given set" scenario on all four targets with a set that gives `HOME` and `XDG_CONFIG_HOME` explicitly.

## 5. User overrides and explicit primary files

Bead: lander-4us.3.5

- [ ] 5.1 Add `user_overrides` for the three layouts with ambiguity checks, and verify the three "Adjacent user overrides" scenarios.
- [ ] 5.2 Read `Explicit(path)` from the `config` value of `DiscoveryOptions` with layout detection by path, and verify the two "Explicit primary file" scenarios.
- [ ] 5.3 Add `local_overrides` (`<app>.local.<ext>` and `config.local.<ext>` next to each primary, role `LocalOverride`, priority 390, ambiguity checks), include it in `app_dirs` and not in `base`, and verify the three "Adjacent local overrides" scenarios and the two "Local overrides in the standard set" scenarios.

## 6. Workspaces and member selection

Bead: lander-4us.3.6

- [ ] 6.1 Add the `*` and `**` matcher with literal other characters, and verify the "Member glob patterns" scenarios with property tests over generated segment lists.
- [ ] 6.2 Add confinement checks that skip and warn, and the rule that the root is never its own member, and verify the two "Member entries stay in the workspace" scenarios.
- [ ] 6.3 Add the enclosing-workspace search that parses ancestors through the core parse and merge with the registered formats, obeys the boundary, and passes over unreadable, ambiguous and non-workspace files, and verify the three "Enclosing workspace discovery" scenarios.
- [ ] 6.4 Add automatic member selection (enclosing, default, single) with key paths from the application, and verify the four "Automatic member selection" scenarios and the "Listed member is missing" scenario.
- [ ] 6.5 Add explicit project selection from the `project` value of `DiscoveryOptions`, by path then by name, with `UnknownProject` and `AmbiguousProject`, and verify the three "Explicit project selection" scenarios.
- [ ] 6.6 Order the project-tier sources with roles `Workspace`, `Member`, `LocalOverride` and `UserOverride` and priorities 300, 350, 390 and 400, and verify the three "Project layer order" scenarios and the "Reports in merge order" and "Member roles" scenarios.

## 7. Member-scope and inherited-layer key filters

Bead: lander-4us.3.7

- [ ] 7.1 Add `member_scope_keys` that declares the core `exclude(paths, warn=true)` on member layers, and verify the "Member cannot set a workspace key" scenario and that the removed key has no `Origin`.
- [ ] 7.2 Add `inherited_filter` that declares the core `exclude(paths, warn=false)` on system, global and workspace layers when a member is selected, and verify the two "Inherited-layer key filter" scenarios.

## 8. Environments

Bead: lander-4us.3.8

- [ ] 8.1 Add `environments(default?)` and resolve the name from `DiscoveryOptions`, then `<PREFIX>_ENVIRONMENT`, then the default, and verify the "Environment name resolution" and "Discovery options from the host" scenarios.
- [ ] 8.2 Add name validation with `ConfigError::InvalidEnvironmentName`, with `user` and `local` reserved in any letter case, and verify the three "Environment name validation" scenarios.
- [ ] 8.3 Add environment-file candidates for project-tier primaries with role `EnvironmentFile` at priority 375, and verify the three "Environment files" scenarios and the "No environment file for global configuration" scenario.
- [ ] 8.4 Document environments, the opt-in and the reserved names that an application without hosting must give, in the package README, and verify that the README example runs.

## 9. Load protocol and host adapters

Bead: lander-4us.3.9

- [ ] 9.1 Make discovery return `Need` with `FileRequest` values for a partial tree and `Done` for a complete one, pass `Need` out of `@config.load`, and verify the three "Pure discovery over the core load protocol" scenarios.
- [ ] 9.2 Verify the "Native adapter reads files" scenario through the core `@config/host.load` in a temporary directory, and verify `mise run test:native-zig` passes.
- [ ] 9.3 After the core `config/host` js story is done, verify the "js adapter reads files" scenario through the TypeScript adapter on the pinned Node.
- [ ] 9.4 Run the tests of 9.2 and 9.3 on the windows-latest CI leg, and verify the "Windows report paths" scenario.
- [ ] 9.5 Verify the "wasm uses injected tree" scenario on wasm and wasm-gc through `@config.load` with a complete tree.

## 10. Morphir preset acceptance fixture

Bead: lander-4us.3.10

- [ ] 10.1 Build the Morphir preset in `tests/` from public parts only (design D16), with YAML limited to `.yaml`, the JSON5 format only on the legacy part, and no local override part, and verify the "Six primary candidates" and "Preset has no local layer" scenarios.
- [ ] 10.2 Port the discovery, precedence, member and ambiguity cases of Morphir's `config.feature` to `tests/config-conventions-acceptance/features/morphir.feature`, and verify they pass with moonspec on js and native.
- [ ] 10.3 Add the merge-rules cases (global ambiguity, `MORPHIR_HOME`, `MORPHIR_LOG_DIR`, relative XDG, macOS and Windows directories, `C:/ProgramData`, legacy `morphir.json`), and verify the "Morphir preset reproduces Morphir" scenarios.
- [ ] 10.4 Run the same cases as snapshot tests in `tests/config-conventions-laws` on all four targets, and verify `mise run test` passes.
- [ ] 10.5 Add a case that shows the inherited-filter difference from the Rust loader (design D9), and verify it passes.
- [ ] 10.6 Update `tests/README.md` with the focused commands for the new suites, and verify each command runs.

## 11. Integration check

Bead: lander-4us.3.11

- [ ] 11.1 Run `mise run check` on the complete change and verify that lint, validation, tests on wasm, wasm-gc, js and native, script tests and builds pass.
