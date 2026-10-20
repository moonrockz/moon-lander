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
  the ID. Tick the tasks in `tasks.md` and close the bead when the group is verified.
- Run `mise exec -- openspec validate --all --strict` after you edit `openspec/`.

## Toolchain and tasks

- Pin tools in `.config/mise/config.toml`. Run `mise trust` and `mise install`.
- Write automation in `scripts/*.mbtx`, run with `moonx`, and expose it as mise
  tasks. Pin imports. Do not replace these tasks with shell or PowerShell scripts.
- Use `moonbitlang/async` for process and filesystem operations. Propagate failures
  through nonzero exit codes.
- Put libraries under `pkgs/` and executables under `apps/`. Register modules in
  `moon.work`. Add acceptance suites under an unpublished `tests/` module when
  there is behavior to test.
- The root `moon.mod` is the version source of truth. Keep member versions and
  source version strings aligned using `scripts/versions.mbtx`.
- Prefer pure domain functions, explicit inputs, immutable public values, and
  typed alternatives. Keep I/O in host adapters and other boundary code.

## Verification

Run `mise run check` after changes. It runs lint, workspace and version validation,
tests for `wasm`, `wasm-gc`, `js`, and `native`, task script tests, and builds.
Run `mise run test:native-zig` when changing native toolchain integration.
Install Lefthook with `mise run hooks:install`. Run `mise run format` before
committing MoonBit changes. Use Conventional Commits without AI attribution.

## Publishing

The module name `moonrockz/moon-lander` is provisional. There is no CLI yet.
Do not add UI packages or a separate regolith module. Consume `zig-cross` through
`moonx`; do not vendor it. Ask before cutting a GitHub release or publishing to
mooncakes.io. The initial setup intentionally has no publishing workflow.
