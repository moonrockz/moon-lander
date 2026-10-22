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
- Use `moonbitlang/async` for process and filesystem operations. Propagate failures
  through nonzero exit codes. Exception: js file access in `config/host` uses the
  TypeScript adapter over `node:fs` in `pkgs/lander/adapters/node/`, built with Bun
  through `scripts/build-node-adapter.mbtx`. Its test fixtures use a separate
  TypeScript entry point and generated test file.
- Browser Web API calls may use TypeScript in `pkgs/lander/adapters/browser/`,
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

## Verification

Run `mise run check` after changes. It runs lint, workspace and version validation,
tests for `wasm`, `wasm-gc`, `js`, and `native`, task script tests, and builds.
Run `mise run test:native-zig` when changing native toolchain integration.
Install Lefthook with `mise run hooks:install`. Run `mise run format` before
committing MoonBit changes. Commit the `pkg.generated.mbti` files that `mise run lint`
writes; lint fails when one is new or changed and not staged. Use Conventional Commits
without AI attribution.

## Publishing

The module name `moonrockz/moon-lander` is provisional. There is no CLI yet.
Do not add UI packages or a separate regolith module. One exception: the unpublished
docs tool `apps/site` can use Rabbita. No other module can import it, and the
published library stays UI-free. Consume `zig-cross` through
`moonx`; do not vendor it. Ask before cutting a GitHub release or publishing to
mooncakes.io. Releases run only through `.github/workflows/release.yml`, which
publishes when an owner-approved version change merges to `main`; never publish
from a workstation.
