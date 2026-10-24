# Proposal: Add the host lifecycle

## Why

Moon-Lander must give MoonBit CLI applications a host that is like .NET
`Microsoft.Extensions.Hosting`. The host must start and stop services in a known
order, handle stop requests and signals, and give exit codes that do not change.
finos/morphir-moonbit is the first consumer. Today each Morphir command connects its
own SIGINT flag, maps exit codes by a string compare (`"Cancelled"` gives 130), and
flushes logs with `defer`. The starbase model under Morphir's Rust CLI skips cleanup
on some Ctrl-C paths and gives shutdown a stale session. The configuration changes
supply layered configuration. This change connects that configuration to a lifecycle.

## What Changes

- Add the package `moonrockz/moon-lander-hosting` (`@hosting`):
  - `HostBuilder[S]`, composed with pipelines (`|>`). It holds the application name,
    the arguments, the starting variable set, the working directory, the
    configuration sources, the services factory, the hosted services, the default
    environment name, the variable prefix and the shutdown timeout.
  - Host starting settings, like .NET `HostApplicationBuilderSettings`:
    `@lander.cli(name, args, env_vars?, working_dir?, environment?)` and the bare
    `@hosting.builder` with the same arguments. An omitted
    variable set or working directory comes from the process on native and js. On
    wasm and wasm-gc, an omitted variable set is empty and an omitted working
    directory is `/`. `|> @hosting.env_vars(vars)` and
    `|> @hosting.working_dir(path)` replace them before the build.
  - One variable set and one working directory for each run. Nothing else reads the
    process environment or the process working directory. The set feeds the
    environment-variable source, the environment-name bootstrap, the conventions
    directory resolution and the core `config/host` adapter. Walk-up discovery
    starts at the working directory. `BuildContext` and `Context[S]` show both
    values.
  - The trait `IntoEnvVars`, with implementations for `Map[String, String]` and
    `Json`, so a test can give the variable set as a map literal or as a JSON
    fixture.
  - `Host[S]` and `Context[S]`. The application defines a typed services record `S`.
    The host builds `S` once. Each command, hook and event handler gets the same
    `Context[S]`. There is no dependency-injection container.
  - A fixed run order. The host parses the arguments first with
    `moonbitlang/core/argparse`. Then it fixes the variable set and the working
    directory, finds the environment name, loads the
    configuration through `@config/host.load` (native, js) or `@config.load` over an
    injected `FileTree` (wasm, wasm-gc, `|> @hosting.files(tree)`), and builds `S`.
  - The environment-variable source. The host adds it with the prefix (default: the
    application name in upper case, `|> @hosting.env_prefix(...)` changes it) and
    reserves `<PREFIX>_ENVIRONMENT` and `<PREFIX>_HOME`.
  - `HostEnvironment`: the application name, an optional environment name and the
    content root. `|> @hosting.default_environment(name)` sets a default name and
    enables environment files.
  - `HostedService` values with an optional `starting`, `start`, `started`,
    `stopping`, `stop` and `stopped` hook. Start goes in registration order. Stop
    goes in reverse order.
  - `Lifetime`: the events started, stopping and stopped, `stop_application`, an
    application exit code, and cheap cancellation checks (`ctx.cancelled()`,
    `ctx.check_cancelled()`) that synchronous code can poll.
  - `StopReason` and `ExitCode`. The exit codes are 0, 1 (unhandled failure),
    2 (configuration or usage error), 130 (SIGINT, Ctrl-C), 143 (SIGTERM, console
    close), 131 (SIGQUIT, Ctrl-Break), or a code that the application sets.
  - `UsageError` for CLI misuse.
  - Parsed domain types with smart constructors, so invalid values cannot exist:
    `ServiceName` and `ExitCode` (0 to 255), and `HostError` for a fault in the
    set-up of a host. `AppName` and its `AppNameError` are in
    `moonrockz/moon-lander-core` (`split-framework-modules`). Later groups add
    types for the variable prefix, the environment name, paths and the shutdown
    timeout.
  - A pure, synchronous phase engine. Drivers run its steps.
  - A configurable shutdown timeout (default 30 seconds).
- Add the package `moonrockz/moon-lander-hosting/console` (native and js):
  - Native: a C signal stub (`native-stub`). On Linux and macOS it handles SIGINT, SIGTERM and
    SIGQUIT. On Windows it handles `CTRL_C_EVENT`, `CTRL_BREAK_EVENT` and
    `CTRL_CLOSE_EVENT`. It records which signal arrived, sets an atomic stop flag, and
    ends the process at once on a second signal, also during synchronous code.
  - js: `process.on` listeners in the hosting TypeScript adapter
    `pkgs/hosting/adapters/node` (built with Bun), beside the `config/host` adapter
    (`split-framework-modules` D2).
  - After a graceful signal stop, the process exits explicitly with 130, 143 or 131 on
    every platform.
- Add a first spike task group. It proves that a C `native-stub` in `hosting/console`
  installs the handlers, ends the process on a second signal, and owns the signals
  without the `moonbitlang/async` runtime on Linux, macOS and Windows, also for a
  consumer module outside the workspace. If the spike fails, the work stops and goes
  back to the owner.
- Add an embedded driver for wasm and wasm-gc. The lifetime stops through
  `stop_application` or through a stop probe that the embedder supplies.
- Add the package `moonrockz/moon-lander-hosting/argparse`. It gives the standard
  flags `--environment`, `--config`, `--isolated` and `--project` (on under `@lander`,
  opt-in on the bare `@hosting.builder`), and maps
  them to the environment name and the conventions `DiscoveryOptions`. It turns mapped
  options into the overrides source of the configuration core (priority 700).
- Add two entry layers (Owner, 2026-10-20: "lean on minimal config and sane
  defaults"). The application name occurs only in the entry call.
  - `@lander.cli(name, args, env_vars?, working_dir?, environment?)` is
    batteries-included. It turns on these defaults: the formats from the `formats`
    virtual package of `add-configuration-core` (all five formats unless the
    application trims them), the `app_dirs` conventions, the standard flags,
    environment-file discovery (files load only when the run has an environment
    name), `S = Unit` until `|> @lander.build(factory)`, and a 30-second shutdown
    timeout. `|> @lander.formats(...)`, `|> @lander.conventions(...)`,
    `|> @lander.no_standard_flags()`, `|> @lander.no_environments()` and
    `|> @lander.shutdown_timeout(ms)` change or turn off a default.
  - `|> @lander.run(command)` selects the console driver on native and js and the
    embedded driver on wasm and wasm-gc. The smallest program is
    `"acme" |> AppName::parse |> @lander.cli(@env.args()) |> @lander.run(fn(ctx) { ... })`.
  - `@hosting.builder` is bare: it turns on none of these defaults. The Morphir preset
    builds on it.
  - The users of an application need no configuration file. A run with no file uses
    the defaults. An empty file is valid. A file sets only the keys that it holds.
- Add a narrow AGENTS.md exception for the C signal stub.

## Capabilities

### New Capabilities

- `host-lifecycle`: the host builder, the typed services record and context, the
  run order, the host environment, the environment-variable source, standard flags,
  hosted-service start and stop order, lifecycle hooks and events, stop requests and
  cancellation checks, signal handling per platform and target, the shutdown timeout,
  exit codes, the argparse adapter, and the batteries-included `@lander` entry with
  its defaults.

### Modified Capabilities

None. This change depends on `configuration-core`, `configuration-conventions` and
`configuration-binding`, but it does not change their requirements.

## Impact

- New packages in the `moonrockz/moon-lander-hosting` module (`pkgs/hosting`, since
  `split-framework-modules`): the root package `@hosting`, `console` and `argparse`.
  The root package `@lander` of `moonrockz/moon-lander` gets the batteries-included entry:
  `cli`, its default steps, `run`, and `pub using` re-exports of `@hosting` steps.
  `@lander` imports the `formats` virtual package of `add-configuration-core`.
- New dependencies: `moonbitlang/async` (task groups, cancellation, timeouts),
  `moonbitlang/core/argparse` and `moonbitlang/core/env`. The native build of
  `hosting/console` compiles a C stub with the consumer's C compiler, which native
  MoonBit builds already need. The js driver uses the hosting TypeScript adapter
  `pkgs/hosting/adapters/node`.
- AGENTS.md: a narrow exception lets `hosting/console` use a C stub for native
  signal handlers. All other process work stays with `moonbitlang/async`.
- Windows is a target. Tests for the native stub and the js driver run on the
  windows-latest CI leg that `add-configuration-core` adds.
- Depends on the changes `add-configuration-core`, `add-configuration-conventions`
  and `add-configuration-binding`. Implement this change after them. The spike can run
  first.
- Acceptance suites go in the unpublished `tests/` module. Signal tests build a small
  test program and send real signals or console events on native and js.
- finos/morphir-moonbit can remove `platform/interruption.mbt`, the per-command
  SIGINT stub in `platform.c`, the string compare for exit codes in
  `apps/morphir/main.mbt`, and the `defer logs.flush()` wiring. A hosted service with
  a `stopping` hook replaces the flush.

## Out of scope

- A dependency-injection container. The owner may add one later.
- Configuration reload when a file changes.
- A CLI parser of our own. Parsing stays with `moonbitlang/core/argparse`.
- A logging abstraction like `Microsoft.Extensions.Logging`. It is future work.
- Long-running background services (a `BackgroundService` equivalent) and concurrent
  service start.
- Signals on wasm and wasm-gc.
- The behavior of configuration sources, merge, discovery and binding. The three
  configuration changes own it.
