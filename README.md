# Moon-Lander

Moon-Lander is an application framework for MoonBit. It has no user interface.

Build an application once and land it on a host. A host can be the web, WebAssembly, or a native process.

[Moonbase](https://github.com/moonrockz/Moonbase) holds the web UI and the Proton desktop shell.

## Development setup

The build setup follows Moonbase and smithy. Install [mise](https://mise.jdx.dev/), then run:

```shell
mise trust
mise install
mise exec -- moon version --all
```

The MoonBit version is pinned in `.config/mise/config.toml`. The mise archive can
omit the core library and `moonx`. If the version check fails or `moonx` is missing,
complete that same installation with the official installer:

```shell
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | \
  MOON_HOME="$(mise where http:moonbit)" bash -s -- "$(mise current http:moonbit)"
```

Then install the hooks and check the workspace:

```shell
mise run hooks:install
mise run browsers:install
mise run check
```

Pre-commit checks formatting and compiler warnings. Pre-push runs lint, workspace
validation, and tests. Local tool overrides belong in
`.config/mise/config.local.toml`, which is gitignored.

Changes to behavior start as OpenSpec changes and are tracked in beads. See
[the contributing guide](CONTRIBUTING.md).

## Tasks

Tasks are MoonBit scripts under `scripts/`, run through `moonx` by mise.

| Command | Purpose |
| --- | --- |
| `mise run check` | Lint, validate, test the library and task scripts, and build |
| `mise run build` | Build `wasm`, `wasm-gc`, `js`, and `native` |
| `mise run test` | Test all four targets |
| `mise run build -- js --release` | Build a selected target in release mode |
| `mise run test -- native` | Test a selected target |
| `mise run format` | Format the workspace |
| `mise run lint` | Check YAML, MoonBit formatting, and compiler warnings |
| `mise run validate` | Check workspace membership and shared versions |
| `mise run test:scripts` | Test the build tooling |
| `mise run check:config` | Run core acceptance and compare complete values, provenance and reports on all four targets |
| `mise run check:formats` | Verify parser trimming, linked format overrides and leak rejection on all four targets |
| `mise run check:formats-registry` | Package the candidate and verify an isolated registry consumer on all four targets |
| `mise run build:site` | Build the docs site into `_site/` (args: `--main`) |
| `mise run dev:site` | Build the docs site, serve it at `http://127.0.0.1:4173/moon-lander/` and build it again after a change |
| `mise run check:site` | Check the links of the built `_site/` |
| `mise run test:site` | Test the docs site packages and the code highlight step |
| `mise run build:node-adapter` | Regenerate the checked-in TypeScript host adapter bundle |
| `mise run check:node-adapter` | Reject a stale host adapter bundle |
| `mise run test:node-adapter` | Test the js host adapter on Node and Bun |
| `mise run browsers:install` | Install the locked Playwright harness and Chromium, Firefox, WebKit; add `-- --with-deps` on Linux |
| `mise run test:browser` | Build the unpublished fixture once and test all three browser engines |
| `mise run test:browser-failures` | Also prove deliberate assertion and unavailable-engine failures propagate |
| `mise run build:browser-fixture` | Generate the spike FFI and build the browser fixture |
| `mise run check:browser-fixture` | Reject a stale generated spike FFI without rewriting it |
| `mise run build:browser-adapter` | Generate the production browser Web API adapter |
| `mise run check:browser-adapter` | Reject stale production browser FFI without rewriting it |
| `mise run test:native-zig` | Test native code using external `moonrockz/zig-cross@0.1.2` |
| `mise run clean` | Remove build artifacts |

## Layout and current scope

- `moon.mod` holds the shared version, currently `0.1.0`.
- `moon.work` lists the workspace members.
- `pkgs/lander/` contains the provisional `moonrockz/moon-lander` library, imported
  as `@lander`. Its `version()` export provides a build and test smoke check. Its
  `config` packages hold the configuration core and `formats` selects the linked
  parsers through a virtual package.
- `pkgs/notebooks/` contains [`moonrockz/notebooks`](pkgs/notebooks/README.md),
  migrated from Moonbase with its existing module name and package paths. It
  provides immutable Jupyter and DIB models, codecs, metadata, typed cursors
  and shared traversal, with runnable usage guides for all four targets.
- `tests/` is an unpublished workspace module containing the notebook acceptance
  suites and property laws. See [the test guide](tests/README.md) for focused runs.
- `openspec/` holds the requirements (`specs/`) and the changes in progress
  (`changes/`). The hosting and configuration framework is proposed there.
- `.config/mise/config.toml` pins the tools and declares tasks.
- `.github/workflows/ci.yml` checks lint, validation, builds, tests, and task scripts.
  The `ci-ok` job is the aggregate check for branch protection.

The application model, host adapters, and CLI are proposed in `openspec/changes/`
and are not implemented yet. No UI packages
are included. CI has read-only permissions and no publishing or release workflow.

## Releases

The `0.1.0` release moves `moonrockz/notebooks` here and adds MIME queries,
runtime cell capability inspection, and Ion-backed metadata with JSON, YAML,
TOML and Ion DIB inputs. See [the changelog](CHANGELOG.md) for API migration notes.

Release versions are shared across workspace members. Only `pkgs/notebooks`
is published to mooncakes.io; the framework name remains provisional. The
workspace root and `tests` are not published. GitHub releases identify the
corresponding source commit with a version tag.

After setting the version with `scripts/versions.mbtx`, run the full check
and validate the package before publishing:

```shell
mise run format
mise run check
mise exec -- moon -C pkgs/notebooks publish --dry-run
mise exec -- moon -C pkgs/notebooks publish
```

Publishing is manual and requires an explicit release request. No workflow
publishes automatically.

License: Apache-2.0.
