# Moon-Lander

Read `README.md` for the workspace layout and commands. Moon-Lander is a MoonBit
application framework with no UI package. Moonbase owns its UI and desktop shell.

## Working preferences

- Use compilers, linters, formatters, static analyzers, and focused tests for the
  issues they can determine. Reserve manual reasoning for behavior, requirements,
  architecture, performance, and concurrency.
- Keep `docs/superpowers/` design and implementation plans local. Never stage or
  commit them. Add that path to `.git/info/exclude` when needed, without changing
  the tracked `.gitignore`. Preserve local files if removing them from an unpushed
  commit.

## Planning and specifications

- Follow `CONTRIBUTING.md` for the OpenSpec and beads workflow. Changes to behavior,
  public APIs or requirements start as an OpenSpec change in `openspec/changes/`.
- Each task group in a change's `tasks.md` is one beads story; its `Bead:` line holds
  the ID. Tick the tasks in `tasks.md` in the pull request.
- Landing a pull request includes the tracker state. Follow "Land a change" in
  `CONTRIBUTING.md`: the last group's pull request archives the change; after the
  merge, close the beads with the PR and merge SHA, close a finished epic, and sync.
- Run `mise exec -- openspec validate --all --strict` after you edit `openspec/`.

## Toolchain and tasks

- Pin tools in `.config/mise/config.toml`. Run `mise trust` and `mise install`.
- Write automation in `scripts/*.mbtx`, run with `moonx`, and expose it as mise
  tasks. Pin imports. Do not replace these tasks with shell or PowerShell scripts.
  Run tasks through mise, or run a script directly as `moonx scripts/toolchain.mbtx scripts/<name>.mbtx`.
  Each task bootstraps with `moonx` from PATH, so the global toolchain must accept the frontmatter import syntax; the wrapper puts the pin first for every nested call.
- Use `moonbitlang/async` for process and filesystem operations. Propagate failures
  through nonzero exit codes. Exception: js file access in `moonrockz/moon-lander-config/host` uses the
  TypeScript adapter over `node:fs` in `pkgs/config/adapters/node/`, built with Bun
  through `scripts/build-node-adapter.mbtx`. Its test fixtures use a separate
  TypeScript entry point and generated test file. The js standard-error write of
  the hosting error report and the js signal listeners of
  `moonrockz/moon-lander-hosting/console` use a TypeScript adapter over `node:*` in
  `pkgs/hosting/adapters/node/`, with the same rules, built by the same script as a
  second entry point. The js console streams and log files of
  `moonrockz/moon-lander-logging-hosting-async/runtime` use a TypeScript adapter over
  `node:process` and `node:fs/promises` in `pkgs/logging-hosting-async/adapters/node/`,
  with the same rules and the same script. It covers only stream writes and the
  terminal check, `mkdir`, exclusive create, append, write, close, `readdir`, `lstat`
  and `unlink`, because the pinned `moonbitlang/async` has no js `fs` or `stdio`;
  native uses `moonbitlang/async`. Do not use it for other Node.js I/O.
- Native signal handlers in `pkgs/hosting/console` use a C stub
  (`signal_stub.c`, a `native-stub`), because `moonbitlang/async` gives no SIGQUIT,
  no signal identity and no handler that runs during code that never yields. The
  stub does only async-signal-safe work. All other process and filesystem work stays
  with `moonbitlang/async`.
- `pkgs/hosting/vendor/` holds a copy of `moonbitlang/core/argparse` with the patch of
  moonbitlang/core#4487 (`Command::try_parse`), until a pinned MoonBit release has it
  (bead `lander-4us.5.18`). Do not edit it; its `README.md` gives the source, the one
  local change and the return steps. Importers keep the alias of the core package,
  and applications use the `@hosting_argparse` type re-exports, so the return changes
  only the `moon.pkg` imports.
- Consult `zig-cross` doctor before you change the zig-cross pin, `ZIG_CROSS_RUNTIME`,
  `sync_programs` in `scripts/cross-build.mbtx` or a cross-build CI job:
  `mise run doctor:zig-cross` (add `-- --json` for the `schema_version: 1` report), on
  each host OS that the change affects. Use the finding codes and `next_steps`, check
  them against the real programs, and record them in the pull request. The sync runtime
  excludes `moonbitlang/async`, so hosting and the config host keep their native macOS
  and Windows CI legs. A cross-built Windows program is not proof of runtime behavior.
  See "Cross-builds with zig-cross" in `README.md`.
- Browser Web API calls may use TypeScript in `pkgs/config/adapters/browser/`,
  bundled with the pinned Bun browser target through moonx. The unpublished
  feasibility fixture and Playwright tests live under `tests/`; HTTP serving,
  installation, build and process lifecycle stay in MoonBit task scripts. No
  published package may contain selection UI or a Node browser shim.
- Put libraries under `pkgs/` and executables under `apps/`. Register modules in
  `moon.work`. Add acceptance suites under an unpublished `tests/` module when
  there is behavior to test.
- The root `moon.mod` is the version source of truth. Keep member versions and
  source version strings aligned using `scripts/versions.mbtx`.
- Prefer pure domain functions, explicit inputs, immutable public values, and
  typed alternatives. Keep I/O in host adapters and other boundary code.

## Domain types

Do not use primitive obsession. Parse, do not validate. Make invalid states
unrepresentable.

- When a value has rules, make a type for it. Do not use a raw `String`, `Int`,
  `Array` or `Map` for it. Examples: names, prefixes, keys, paths, durations, ports
  and exit codes.
- Give each type a smart constructor, for example
  `AppName::parse(text) -> AppName raise NameError`. Keep the fields private, so the
  constructor is the only way to make a value. Do not use a `pub(all)` struct or a
  public tuple struct for a value that has rules.
- Parse one time, at the boundary where the raw value enters. After the parse, pass
  the type, not the raw value. Do not check the same rules again later.
- Use an enum for a fixed set of cases, not a string or an integer code.
- When a value is valid by construction, give a constructor that cannot fail, for
  example a constant (`ExitCode::success()`) or a value derived from another valid
  value (a default prefix from an `AppName`).
- A parse failure is a typed `suberror` that names the input and the rule it breaks.
- Test each rule of a smart constructor with values on each side of the limit.

## Testable design

Prefer designs that are naturally testable. A unit test should check behavior
through public values, without real time, real I/O or a running event loop where
possible.

- Describe work as values and let one small runtime run them, so a test can run
  the same value with a deterministic runner. Actor receives are the model.
- Give time, randomness and I/O as explicit inputs or host adapters.
- In async tests, use acknowledgements for ordering. Use a sleep only for a real
  deadline test.
- When two designs are otherwise equal, choose the one that a test can check
  without a scope, a task group or a host.
- Benchmarks are local tools. Run them through a manual mise task, never in
  `mise run check`, CI or the release workflow.

## Verification

Run `mise run check` after changes. It runs lint, workspace and version validation,
tests for `wasm`, `wasm-gc`, `js`, and `native`, task script tests, and builds.
Run `mise run test:native-zig` and `mise run build:cross` when changing native toolchain
integration.
Install Lefthook with `mise run hooks:install`. Run `mise run format` before
committing MoonBit changes. Commit the `pkg.generated.mbti` files that `mise run lint`
writes; lint fails when one is new or changed and not staged. Use Conventional Commits
without AI attribution.

## Review guidelines

Review each change against this file. The full checklist is the skill
`.agents/skills/code-review/SKILL.md`. It is the one source for every agent tool:
the `code-reviewer` agents in `.claude/agents/`, `.cursor/agents/`,
`.codex/agents/` and `.github/agents/` only point to it. A tool without one of
these formats reads the skill file directly. Change the checklist only in the
skill. Report these as problems:

- A raw primitive for a domain value that has rules, a check that repeats rules after
  a parse, or a public way to make a value that breaks its rules (Domain types).
- I/O outside host adapters and drivers, or mutable public state.
- Behavior, a public API or a requirement that changes without an OpenSpec change,
  or code that disagrees with the spec, the design or the ticked tasks.
- Library code that does not build and test on `wasm`, `wasm-gc`, `js` and `native`,
  or a `warnings` override in `moon.pkg` without a comment that gives the reason and
  when to remove it.
- A changed public API without its `pkg.generated.mbti` update.
- A design that is not naturally testable, or a benchmark in `mise run check`, CI or
  the release workflow (Testable design).

## Publishing

The framework is eight modules: `moonrockz/moon-lander-core`,
`moonrockz/moon-lander-logging`, `moonrockz/moon-lander-config`, `moonrockz/moon-lander-mediator`,
the optional `moonrockz/moon-lander-logging-hosting-async`, the optional
`moonrockz/moon-lander-actors`, `moonrockz/moon-lander-hosting` and the umbrella
`moonrockz/moon-lander`. Each imports only the modules below it
(`mise run validate` checks this). The logging module imports only the MoonBit core
library; `logging-hosting-async` imports core, logging and `moonbitlang/async`, never
config, mediator or hosting; `actors` imports core and `moonbitlang/async` only. The module names are provisional. There is no CLI yet.
Do not add UI packages or a separate regolith module. One exception: the unpublished
docs tool `apps/site` can use Rabbita. No other module can import it, and the
published library stays UI-free. Consume `zig-cross` through
`moonx`; do not vendor it. Ask before cutting a GitHub release or publishing to
mooncakes.io. Releases run only through `.github/workflows/release.yml`, which
publishes when an owner-approved version change merges to `main`; never publish
from a workstation.

## Shared OpenSpec configuration

Use the shared `html-design` schema for new changes. Read `openspec/README.md`
and `openspec/config.yaml`; repository-local tracking and approval rules still apply.
The files under `openspec/schemas/html-design/` and `scripts/openspec-ext.mbtx`
are managed by Mission Control's openspec-ext bundle. Change the shared source
and reinstall instead of editing these snapshots. Run `mise run openspec:check`
and `mise exec -- openspec validate --all --strict` after configuration changes.
OpenSpec artifacts are committed project documentation; existing scratch-document
rules continue to apply to local notes. Existing changes retain their own schema.
