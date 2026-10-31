# Moon-Lander

<p align="center">
  <img src="docs/assets/moon-lander-badge.png" alt="The pink Moonrockz bunny piloting a gold lunar lander above the moon-lander wordmark" width="360" />
</p>

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

## Compose configuration profiles

Opt in to ordered profiles such as `postgres` and `metrics`, with separate
`acme.profile.metrics.toml` files, includes and reusable groups. Profiles load
after environment files and before local overrides. The loaded configuration
records immutable membership for factories, hooks and commands. See the
[profile policy guide](pkgs/config/profiles/README.mbt.md) and the
[discovery guide](pkgs/config/conventions/README.mbt.md#compose-configuration-profiles).

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
Run tasks through mise, or run a script directly as `moonx scripts/toolchain.mbtx scripts/<name>.mbtx`.

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
| `mise run check:actors` | Fail when the actor policy root, the actor runtime or the actor acceptance suite runs zero tests on a target |
| `mise run bench:actors` | Run the local actor receive benchmark in release mode. A manual tool: `check`, CI and the release workflow never run it |
| `mise run check:sigstore` | Fail when the sigstore root package or one of its internal packages runs zero tests on a target |
| `mise run bench:sigstore` | Time one Sigstore bundle verification in release mode on all four targets. A manual tool: `check`, CI and the release workflow never run it |
| `mise run check:logging` | Fail when a portable logging package (root, formatting, rolling, sink settings) or the acceptance suite runs zero tests on a target |
| `mise run check:logging-sinks` | Run console, file, drain and signal scenarios in native, Node.js and Bun children, the ESM load, and the isolated logging consumers |
| `mise run check:config` | Run core/profile acceptance, native/js profile files, and compare complete observations on all four targets |
| `mise run check:formats` | Verify parser trimming, linked format overrides and leak rejection on all four targets |
| `mise run check:framework-registry` | Audit all twelve candidate archives and build isolated registry consumers on supported targets |
| `mise run check:framework-published` | Release-only gate for all twelve public archives and approved checksums |
| `mise run check:moonx` | Qualify the optional launcher with the primary stock compiler and a real Node-owned host |
| `mise run check:moonx-stock16` | Qualify the same public APIs with pinned stock 0.10.16 |
| `mise run check:moonx-runtime` | Reconstruct and verify frozen source, patches, licenses and provenance |
| `mise run check:moonx-retained` | Run retained upstream native and Wasm tests sequentially |
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
| `mise run build:sigstore-assets` | Generate the pinned Sigstore public-good and GitHub roots and the test fixtures from `pkgs/sigstore/testdata/` |
| `mise run check:sigstore-assets` | Reject a stale Sigstore root or fixture file, or changed test data, without rewriting |
| `mise run build:site` | Build the docs site into `_site/` (args: `--main`, `--tree next` for `_site/next/`, or `--tree <minor>` for `_site/v/<minor>/`) |
| `mise run dev:site` | Build the docs site, serve it at `http://127.0.0.1:4173/moon-lander/` and build it again after a change |
| `mise run check:site` | Check the links of the built `_site/`, or of one tree with `--tree`; an assembled site is checked tree by tree |
| `mise run test:site` | Test the docs site packages and the code highlight step, and run the browser smoke test on the built site (args: `--tree`) |
| `mise run assemble:site` | Add the site assets of the releases to a `next` build and write the versioned site (CI deploy; needs `gh`) |
| `mise run build:node-adapter` | Regenerate the checked-in TypeScript host adapter bundle |
| `mise run check:node-adapter` | Reject a stale host adapter bundle |
| `mise run test:node-adapter` | Test the js host adapter on Node and Bun |
| `mise run browsers:install` | Install the locked Playwright harness and Chromium, Firefox, WebKit; add `-- --with-deps` on Linux |
| `mise run test:browser` | Build the unpublished fixture once and test all three browser engines; `-- --engines chromium,firefox` selects engines |
| `mise run test:browser-zig` | Run the browser suite with zig as the C compiler, as CI does in the Playwright image |
| `mise run test:browser-failures` | Also prove deliberate assertion and unavailable-engine failures propagate |
| `mise run build:browser-fixture` | Generate the spike FFI and build the browser fixture |
| `mise run check:browser-fixture` | Reject a stale generated spike FFI without rewriting it |
| `mise run build:browser-adapter` | Generate the production browser Web API adapter |
| `mise run check:browser-adapter` | Reject stale production browser FFI without rewriting it |
| `mise run test:native-zig` | Test native code using external `moonrockz/zig-cross@0.3.0` |
| `mise run doctor:zig-cross` | Diagnose zig-cross targets without building (args: targets, `--json`) |
| `mise run build:cross` | Run doctor, then cross-build Linux arm64, macOS and Windows programs (args: plans `full`, `sync` or target names) |
| `mise run clean` | Remove build artifacts |

## Cross-builds with zig-cross

`moonrockz/zig-cross` compiles MoonBit native code with Zig. The tasks use it
through `moonx` at the pin in `.config/mise/config.toml`; do not copy its
wrappers. It runs on Linux and macOS, not on Windows.

Run doctor first. It reads the toolchain and the selected runtime, and does not
build anything:

```shell
mise run doctor:zig-cross -- linux-x64 darwin-arm64 windows-x64
ZIG_CROSS_RUNTIME=sync mise run doctor:zig-cross -- --json
```

The JSON report (`schema_version: 1`) has a status, and findings with stable
codes and next steps. Status `error` exits with 1. In a next step, replace
`zig-cross` with `mise exec -- moonx scripts/toolchain.mbtx moonrockz/zig-cross@<version>`
(for `zig-cross doctor <args>`, `mise run doctor:zig-cross -- <args>` is
enough). Replace example paths such as `fixtures/consumer` with a program of
this workspace, such as `tests/formats-default`.

`mise run build:cross` runs doctor, stops on status `error`, and then builds
these plans. It checks the header of each executable. It does not run them.
Arguments select plans (`full`, `sync`) or single targets (`darwin-x64`). CI
runs `mise run build:cross -- linux-arm64 darwin-x64`: the targets that no CI
machine builds. The macOS and Windows jobs build `darwin-arm64` and
`windows-x64` natively, and run the programs.

| Plan | Runtime | Targets | Programs |
| --- | --- | --- | --- |
| `full` | full (default) | `linux-arm64` | `full_programs`: `tests/console-host-program` (hosting, the console signal stub and `moonbitlang/async`) and the sync programs |
| `sync` | experimental `ZIG_CROSS_RUNTIME=sync` | `darwin-arm64`, `darwin-x64`, `windows-x64` | Only the programs in `sync_programs` of `scripts/cross-build.mbtx` |

What a Linux machine can and cannot do, with zig-cross `0.3.0`, MoonBit
`0.10.17+d971670cd` and Zig `0.17.0`:

| Code | What doctor reports | Result for Moon-Lander |
| --- | --- | --- |
| `ZC_LINUX_NAME_MAX` | Linux targets get `-include limits.h` | Linux x64 and arm64 build with the full runtime, also `moonbitlang/async` and the hosting signal stub. The plan builds only arm64, because the Linux x64 jobs already build and run x64 with gcc and with zig |
| `ZC_DARWIN_VNODE_HEADER` | The full runtime needs the macOS SDK; on Linux this is an error | Use the sync runtime, or build on macOS |
| `ZC_WINDOWS_MSVC_RUNTIME` | The full runtime needs MSVC | Use the sync runtime, or build on Windows |
| `ZC_COMPATIBILITY_MODE` | Sync runtime selected; no event loop, async file system, network, processes, TLS, thread pools or watchers | Programs that do not import `moonbitlang/async` link for Darwin and Windows |
| `ZC_WINDOWS_OSSTRING` | A cross-built Windows program can read arguments, environment variables and paths wrongly | Do not ship or trust a cross-built Windows program ([moon#2320](https://github.com/moonbitlang/moon/issues/2320)) |

`moonbitlang/async` does not cross-build to Darwin or Windows in either runtime.
Its own C files need `sys/vnode.h` from the macOS SDK and MSVC. The hosting and
configuration host packages use it, so CI runs them natively with the compiler
of each OS: on macOS, the native legs of `check:console`, `check:config` and
`check:formats`; on Windows, also `mise run test -- native`. That is the
recovery that doctor gives for excluded APIs.

Before you add a program to `sync_programs`, run
`ZIG_CROSS_RUNTIME=sync mise run doctor:zig-cross` and
`mise run build:cross -- sync`. Before you change the zig-cross pin, a runtime
mode or the CI cross-build job, run doctor on Linux and macOS. Record the codes
in the pull request. Change the pin in `scripts/cross-build.mbtx`,
`.config/mise/config.toml` and this file together; `mise run test:scripts` fails
when a `moonrockz/zig-cross@<version>` reference differs from the pin of the
script. Also update the assessed versions above.

## Layout and current scope

- `moon.mod` holds the shared version, currently `0.10.0`.
- `moon.work` lists the workspace members.
- `pkgs/core/` contains [`moonrockz/moon-lander-core`](pkgs/core/README.mbt.md),
  imported as `@lander_core`: the shared domain types `AppName` and `TimeLimit`.
- `pkgs/logging/` contains
  [`moonrockz/moon-lander-logging`](pkgs/logging/README.mbt.md), imported as
  `@logging`: the bring-your-own `Logger` trait, structured log events with
  message templates, and the built-in loggers.
- `pkgs/config/` contains
  [`moonrockz/moon-lander-config`](pkgs/config/README.mbt.md), imported as
  `@config`. The configuration core is the module root. `parsers/<name>` holds
  the format parsers, the `formats` virtual package selects the linked parsers,
  and `conventions`, `host` and `browser` hold discovery and the host adapters.
  `adapters/` holds the TypeScript adapters.
- `pkgs/logging/` also holds the pure `formatting` package (UTC timestamps, the
  Literate console, text and JSON Lines layouts) and the pure `rolling` package
  (file names, rolling plans and retention), on all four targets.
- `pkgs/mediator/` contains
  [`moonrockz/moon-lander-mediator`](pkgs/mediator/README.mbt.md), imported as
  `@mediator`, and the async mediator `moonrockz/moon-lander-mediator/async`
  (`@mediator_async`).
- `pkgs/logging-hosting-async/` contains the optional
  [`moonrockz/moon-lander-logging-hosting-async`](pkgs/logging-hosting-async/README.mbt.md):
  typed sink settings and reports at the root (all four targets), and bounded
  console and rolling file sessions in `runtime` (native, and js on Node.js and
  Bun). `adapters/node/` holds its TypeScript adapter. It imports core, logging
  and `moonbitlang/async`, never config or hosting.
- `pkgs/actors/` contains the optional
  [`moonrockz/moon-lander-actors`](pkgs/actors/README.mbt.md): local typed actors.
  The portable policy types are at the root, imported as `@policy` (all four
  targets). The actor runtime is in `runtime`, imported as `@actors` (wasm, js
  and native). It imports only core, `moonbitlang/async` and `moonrockz/ion`,
  with only the `moonrockz/ion/ion` package from Ion. It never imports logging,
  config, mediator or hosting.
- `pkgs/hosting/` contains
  [`moonrockz/moon-lander-hosting`](pkgs/hosting/README.mbt.md), imported as
  `@hosting`: the host builder, hosted services and `run`, the native console
  signal stub in `console`, and the opt-in logging bridge in `logging`, which
  drains a logging session before the console driver ends the process.
- `pkgs/lander/` contains the `moonrockz/moon-lander` library, imported
  as `@lander`: the `cli` entry, the re-exports, and `version()`, which provides a
  build and test smoke check.
- `pkgs/moonx/` contains the optional
  [`moonrockz/moon-lander-moonx`](pkgs/moonx/README.mbt.md): immutable portable
  process/payload plans and a Wasm/native driver with an isolated frozen runtime.
  It owns original POSIX signal forwarding and private Node payload cleanup.
  Stock Windows Moonrun delivers Ctrl-C as Ctrl-Break with genuine Node-host
  Quit/131; the guide documents this limitation and full parent status. The
  [public `/launch` command](pkgs/moonx/launch/README.md) is a thin driver caller;
  application result schemas stay application-owned. No other framework module
  imports it, and its executable must not mix with canonical async.
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
- `pkgs/sigstore/` contains [`moonrockz/sigstore`](pkgs/sigstore/README.mbt.md),
  imported as `@sigstore`. It verifies Sigstore bundles and GitHub artifact
  attestations against a trusted root, a publisher identity policy and a given
  time, on all four targets. It does no network, file or clock I/O. It embeds
  the pinned Sigstore public-good root and the root of GitHub's Sigstore
  instance, so it verifies public-repository, private-repository and
  immutable-release attestations. DER, X.509, ECDSA, SCT, RFC 3161 and
  transparency-log checks are internal packages. Like `moonrockz/openrpc`, it is
  not a framework layer: it imports `moonbitstack/mooncrypt` and no Moon-Lander
  module. Its requirements are in `openspec/specs/sigstore-bundle-verification/`,
  `openspec/specs/sigstore-signed-timestamps/`, `openspec/specs/sigstore-trusted-root/`
  and `openspec/specs/sigstore-identity-policy/`.
- `apps/site/` is the unpublished docs site tool `moonrockz/moon-lander-site`. It
  builds the static site at `https://moonrockz.github.io/moon-lander/` with
  `moonrockz/telescope@0.5.1`. It owns the Moon-Lander landing page and content adapters.
- `tests/` is an unpublished workspace module containing the notebook acceptance
  suites and property laws. See [the test guide](tests/README.md) for focused runs.
- `openspec/` holds the requirements (`specs/`) and the changes in progress
  (`changes/`). The hosting and configuration framework is proposed there.
- `.config/mise/config.toml` pins the tools and declares tasks.
- `.github/workflows/ci.yml` checks lint, validation, builds, tests, task scripts,
  zig builds and cross-builds. The `ci-ok` job is the aggregate check for branch
  protection.

The application model, command and service lifecycle, and CLI are proposed in
`openspec/changes/` and are not implemented yet. The configuration file host
adapters are implemented. No UI packages are included. One exception: the
unpublished docs tool `apps/site` can use Rabbita. No other module can import it,
and the published library stays UI-free. CI has read-only permissions. `.github/workflows/release.yml`
publishes releases.

## Releases

The `0.9.0` release adds the optional Moonx parent launcher with typed process
plans, private Node payloads and completion after cleanup. POSIX preserves
original SIGINT/SIGTERM. Stock Windows Moonrun delivers Ctrl-C as Ctrl-Break,
with genuine Node-host Quit/131 and the original parent cause and status.
See the [launcher guide](pkgs/moonx/GUIDE.md). Run its public command with
`moonx moonrockz/moon-lander-moonx/launch@0.9.0 --json --help`.

The `0.8.0` release adds the optional typed actors module, notebook virtual file
trees and DIB/Jupyter source conversion. It also adds the branded Telescope docs
site and landing page. Actors are the tenth published library; their runtime
supports wasm, JavaScript and native. See the [actors guide](pkgs/actors/README.mbt.md)
and [notebook conversion guide](pkgs/notebooks/conversion/README.mbt.md).

The `0.7.3` patch adds optional completion reporting to console and logging
bridge entry points. The `0.7.2` patch makes async sender and basic middleware
composition portable to wasm-gc, including non-suspending sends under the embedded
host. See the [async mediator guide](pkgs/mediator/async/README.mbt.md).

The `0.7.1` patch adds enclosing signal probes and real hosted session shutdown
to the console logging bridge. See the [bridge guide](pkgs/hosting/logging/README.mbt.md).

The `0.7.0` release adds opt-in layered workspace discovery, enclosing-host
shutdown controls, lossless DIB source mode and named-object JSON logging.

The `0.6.0` release published all seven framework modules to mooncakes.io,
alongside notebooks and OpenRPC, with exact shared-version dependencies.

The `0.5.0` release adds console and rolling file logging: the optional
`moonrockz/moon-lander-logging-hosting-async` module and the host bridge that
drains the logs before the process ends. The `0.4.0` release splits the framework into six modules, adds the
application host (`moonrockz/moon-lander-hosting`) and the logging module, and
types the configuration file-tree paths. The `0.3.0` release changes the mediator publish policy (every handler runs,
then one `PublishFailed`) and adds the async mediator to the
framework module; it is the first release with a docs site asset. The `0.2.0`
release adds `moonrockz/openrpc`, a portable OpenRPC document library. The `0.1.0` release moved `moonrockz/notebooks` here and added MIME
queries, runtime cell capability inspection, and Ion-backed metadata. See
[the changelog](CHANGELOG.md) for details and API migration notes.

Release versions are shared across workspace members. The framework modules
listed above, `moonrockz/notebooks`, `moonrockz/openrpc` and `moonrockz/sigstore`
are in the publication allowlist and publish to mooncakes.io. The optional
`moonrockz/moon-lander-moonx` is the eleventh library, and `moonrockz/sigstore`,
first published in `0.10.0`, is the twelfth. Install a module at an exact version,
for example `moon add moonrockz/moon-lander@0.10.0`. The workspace root, docs site, `tests`
and generated consumers are private and excluded by the publication allowlist.
GitHub releases identify the source commit with a `vX.Y.Z` tag.

Releases run in GitHub Actions, never from a workstation. Prepare a release
pull request that sets the version with `scripts/versions.mbtx set X.Y.Z` and
adds the `## X.Y.Z` section to `CHANGELOG.md`. The Release workflow dry-runs
its checks on that pull request. Merging it to `main` is the owner's approval:
the workflow then runs the full check, publishes the public modules with the
`MOONCAKES_USER_TOKEN` organization secret, verifies all twelve published archives against approved checksums, runs isolated
registry consumers and the format override checks on supported targets, and creates the GitHub
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
