# Moon-Lander

Moon-Lander is an application framework for MoonBit. It has no user interface.

Build an application once and land it on a host. A host can be the web, WebAssembly, or a native process.

[Moonbase](https://github.com/moonrockz/Moonbase) holds the web UI and the Proton desktop shell.

## Choose the configuration parsers you ship

Applications get TOML, YAML, JSON/JSON5 and Ion through the `formats` virtual
package. One override in the executable's `moon.pkg` selects TOML only, with no
application source change. A consumer can also provide its own format set.
Unused parsers can then be omitted from the linked output.

The [format selection guide](pkgs/config/formats/README.mbt.md) shows the builder
code, the TOML-only override, a custom combination, and the MoonBit
virtual-package feature that enables this build-time selection.

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
| `mise run lint` | Check YAML, MoonBit formatting, compiler warnings, and checked-in `pkg.generated.mbti` interfaces |
| `mise run validate` | Check workspace membership and shared versions |
| `mise run test:scripts` | Test the build tooling |
| `mise run check:mediator` | Fail when the mediator package or its acceptance suite runs zero tests on a target |
| `mise run check:config` | Run core acceptance and compare complete values, provenance and reports on all four targets |
| `mise run check:formats` | Verify parser trimming, linked format overrides and leak rejection on all four targets |
| `mise run check:formats-registry` | Package the candidate and verify an isolated registry consumer on all four targets |
| `mise run check:formats-published` | Release-only gate for the public registry candidate on all four targets |
| `mise run check:openrpc-assets` | Verify pinned OpenRPC and draft-07 sources and deliberate asset failures |
| `mise run check:openrpc` | Verify the OpenRPC library and isolated source consumer on all four targets |
| `mise run check:openrpc-registry` | Package the OpenRPC candidate and verify it through a loopback registry consumer on all four targets |
| `mise run check:openrpc-published` | Release gate: verify the published OpenRPC module from the public registry |
| `mise run qualify:openrpc` | Compare the library with independent Ajv and the frozen corpus on all four targets |
| `mise run qualify:openrpc-failures` | Prove that deliberate qualification failures exit nonzero (also run by `test:scripts`) |
| `mise run build:openrpc-artifacts` | Generate the pinned OpenRPC artifact metaschemas from frozen assets |
| `mise run check:openrpc-artifacts` | Reject stale artifact metaschemas and the associated OpenRPC license |
| `mise run build:openrpc-unicode` | Generate portable regex identifier tables from frozen Unicode data |
| `mise run check:openrpc-unicode` | Reject stale identifier tables and the associated Unicode license |
| `mise run build:site` | Build the docs site into `_site/` (args: `--main`, `--tree next` for `_site/next/`, or `--tree <minor>` for `_site/v/<minor>/`) |
| `mise run dev:site` | Build the docs site, serve it at `http://127.0.0.1:4173/moon-lander/` and build it again after a change |
| `mise run check:site` | Check the links of the built `_site/`, or of one tree with `--tree`; an assembled site is checked tree by tree |
| `mise run test:site` | Test the docs site packages and the code highlight step, and run the browser smoke test on the built site (args: `--tree`) |
| `mise run assemble:site` | Add the site assets of the releases to a `next` build and write the versioned site (CI deploy; needs `gh`) |
| `mise run build:node-adapter` | Regenerate the checked-in TypeScript host adapter bundle |
| `mise run check:node-adapter` | Reject a stale host adapter bundle |
| `mise run test:node-adapter` | Test the js host adapter on Node and Bun |
| `mise run browsers:install` | Install the locked Playwright harness and Chromium, Firefox, WebKit; add `-- --with-deps` on Linux |
| `mise run test:browser` | Build the unpublished fixture once and test all three browser engines |
| `mise run test:browser-zig` | Run the browser suite with zig as the C compiler, as CI does in the Playwright image |
| `mise run test:browser-failures` | Also prove deliberate assertion and unavailable-engine failures propagate |
| `mise run build:browser-fixture` | Generate the spike FFI and build the browser fixture |
| `mise run check:browser-fixture` | Reject a stale generated spike FFI without rewriting it |
| `mise run build:browser-adapter` | Generate the production browser Web API adapter |
| `mise run check:browser-adapter` | Reject stale production browser FFI without rewriting it |
| `mise run test:native-zig` | Test native code using external `moonrockz/zig-cross@0.1.2` |
| `mise run clean` | Remove build artifacts |

## Layout and current scope

- `moon.mod` holds the shared version, currently `0.3.0`.
- `moon.work` lists the workspace members.
- `pkgs/core/` contains [`moonrockz/moon-lander-core`](pkgs/core/README.mbt.md),
  imported as `@lander_core`: the shared domain types `AppName` and `TimeLimit`.
- `pkgs/config/` contains
  [`moonrockz/moon-lander-config`](pkgs/config/README.mbt.md), imported as
  `@config`. The configuration core is the module root. `parsers/<name>` holds
  the format parsers, the `formats` virtual package selects the linked parsers,
  and `conventions`, `host` and `browser` hold discovery and the host adapters.
  `adapters/` holds the TypeScript adapters.
- `pkgs/mediator/` contains
  [`moonrockz/moon-lander-mediator`](pkgs/mediator/README.mbt.md), imported as
  `@mediator`, and the async mediator `moonrockz/moon-lander-mediator/async`
  (`@mediator_async`).
- `pkgs/lander/` contains the provisional `moonrockz/moon-lander` library, imported
  as `@lander`. Its `version()` export provides a build and test smoke check.
- `pkgs/notebooks/` contains [`moonrockz/notebooks`](pkgs/notebooks/README.md),
  migrated from Moonbase with its existing module name and package paths. It
  provides immutable Jupyter and DIB models, codecs, metadata, typed cursors
  and shared traversal, with runnable usage guides for all four targets.
- `pkgs/openrpc/` contains the [`moonrockz/openrpc`](pkgs/openrpc/README.mbt.md)
  document library: typed OpenRPC 1.3.2/1.4.x and draft-07 models, exact JSON,
  source-preserving reading and edits, explicit reference resolution, profiled
  validation and canonical writing. Its requirements are in
  `openspec/specs/openrpc-documents/` and `openspec/specs/openrpc-rollout/`;
  Smithy consumes the published `0.2.0`.
- `apps/site/` is the unpublished docs site tool `moonrockz/moon-lander-site`. It
  builds the static site at `https://moonrockz.github.io/moon-lander/` with Rabbita.
- `tests/` is an unpublished workspace module containing the notebook acceptance
  suites and property laws. See [the test guide](tests/README.md) for focused runs.
- `openspec/` holds the requirements (`specs/`) and the changes in progress
  (`changes/`). The hosting and configuration framework is proposed there.
- `.config/mise/config.toml` pins the tools and declares tasks.
- `.github/workflows/ci.yml` checks lint, validation, builds, tests, and task scripts.
  The `ci-ok` job is the aggregate check for branch protection.

The application model, command and service lifecycle, and CLI are proposed in
`openspec/changes/` and are not implemented yet. The configuration file host
adapters are implemented. No UI packages are included. One exception: the
unpublished docs tool `apps/site` can use Rabbita. No other module can import it,
and the published library stays UI-free. CI has read-only permissions. `.github/workflows/release.yml`
publishes releases.

## Releases

The `0.3.0` release changes the mediator publish policy (every handler runs,
then one `PublishFailed`) and adds the async mediator to the unpublished
framework module; it is the first release with a docs site asset. The `0.2.0`
release adds `moonrockz/openrpc`, a portable OpenRPC document library. The `0.1.0` release moved `moonrockz/notebooks` here and added MIME
queries, runtime cell capability inspection, and Ion-backed metadata. See
[the changelog](CHANGELOG.md) for details and API migration notes.

Release versions are shared across workspace members. `pkgs/notebooks` and
`pkgs/openrpc` are published to mooncakes.io; the framework name remains
provisional, and the workspace root, docs site and `tests` are not published.
GitHub releases identify the source commit with a `vX.Y.Z` tag.

Releases run in GitHub Actions, never from a workstation. Prepare a release
pull request that sets the version with `scripts/versions.mbtx set X.Y.Z` and
adds the `## X.Y.Z` section to `CHANGELOG.md`. The Release workflow dry-runs
its checks on that pull request. Merging it to `main` is the owner's approval:
the workflow then runs the full check, publishes the public modules with the
`MOONCAKES_USER_TOKEN` organization secret, verifies the published OpenRPC
archive from the public registry on all four targets, and creates the GitHub
release. See [the contributing guide](CONTRIBUTING.md).

Each GitHub release from `0.3` on carries the docs site of its minor line as the
asset `site-<minor>.tar.gz`. The Release workflow builds it through
`.github/workflows/site-asset.yml`. The Site workflow downloads the asset of the
newest release of each minor line and serves it at `/moon-lander/v/<minor>/`,
with the newest release also at the root and at `/latest/`, and `main` at
`/next/`. Releases `0.1.0` and `0.2.0` have no site asset, so `versions.since`
in `site/site.json` is `0.3`. Until a `0.3` release exists, the root shows `main`
with a pre-release banner.

License: Apache-2.0.
