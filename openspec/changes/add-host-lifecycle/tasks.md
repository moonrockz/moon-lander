# Tasks

Epic: lander-4us.5

Do group 1 first. It is a feasibility spike for the native C signal stub. If any task in
group 1 fails, record the failure in the bead and stop for the owner. Groups 2 to 4, 10 and 13 need only the core tracer bullet. Group 5 also needs core
group 14, which declares the `Decode` case and `BindFailure`. Groups 6 to 9 and 14 start
after the `add-configuration-conventions` and `add-configuration-binding` integration
checks. Group 16 starts after groups 6 to 13 and core group 18 (the `formats` virtual
package). The bead dependencies record this order. Run `mise run check`
after each group. Run `mise run format` before each commit. The windows-latest CI leg
and the bun pin come from `add-configuration-core`.

## 1. Feasibility spike: C signal stub in hosting/console

Bead: lander-4us.5.1

- [x] 1.1 Write one C source in `hosting/console`, listed in `native-stub` in `moon.pkg`, that exports C-ABI functions (install handlers, read the stop flag, read the signal identity); call them through `extern "c"`; verify `moon test --target native` calls an exported function
- [x] 1.2 Install SIGINT, SIGTERM and SIGQUIT handlers on Linux and macOS, and a `SetConsoleCtrlHandler` handler for `CTRL_C_EVENT`, `CTRL_BREAK_EVENT` and `CTRL_CLOSE_EVENT` on Windows (`#ifdef _WIN32`); verify a test that sends each signal or event and reads the flag and the identity, and record in the bead any Windows event that a CI runner cannot send
- [x] 1.3 Verify a second signal ends the process from inside the handler with the mapped code (130, 143, 131) while the main thread runs a loop with no suspension point; run the loop in a helper executable started as a child process through `moonbitlang/async/process`
- [x] 1.4 Verify the `moonbitlang/async` runtime does not also handle the same signals when the stub is active, with `@signal.set_global_cancellation_signals([])`, on each platform
- [x] 1.5 Run 1.1 to 1.4 on Linux, macOS and Windows CI legs, and with `mise run test:native-zig`; verify all pass
- [x] 1.6 Verify a consumer module outside the workspace that depends on `moonrockz/moon-lander` by path builds the stub with its own C compiler and passes 1.1 to 1.4 on Linux and macOS
- [x] 1.7 After 1.1 to 1.6 pass, add a narrow exception to AGENTS.md: native signal handlers in `hosting/console` use a C stub; all other process and filesystem work stays with `moonbitlang/async`

## 2. Tracer bullet: one service, one command, one exit code

Bead: lander-4us.5.2

- [x] 2.1 Create the package `moonrockz/moon-lander-hosting` and add `moonbitlang/async` (exact version) to the module; verify `mise run build` passes on wasm, wasm-gc, js and native
- [x] 2.2 Add `HostBuilder[S]`, `@hosting.builder`, `service` (with `start` and `stop` only), `build` and `Host[S]` with no configuration (an empty in-memory source); verify a test that builds a `Host[Unit]` on all four targets
- [x] 2.3 Add a first `@hosting.run` (native, js) that builds `S`, runs `start`, the command and `stop`, and returns a `RunOutcome` with exit code 0 or 1; verify tests for a clean run and a failing command, also on the Windows leg
- [x] 2.4 Add the `@lander.cli(name, args)` shortcut. Rename `pkgs/lander/README.md` to `README.mbt.md` and set `readme` in `pkgs/lander/moon.mod` to it. Add an example that builds a host (`cli`, `service`, `build`); verify that the example compiles as a doc test on all four targets, and that a native and js test runs the same host with `@hosting.run`
- [x] 2.5 Add `AppName`, `ServiceName` and `ExitCode` with smart constructors, and `HostError` (design D17); make `@hosting.builder`, `@lander.cli` and `service` take the types, and make `service` reject a second service whose name differs only in letter case; verify each rule on both sides of its limit and the scenarios of "Parsed names and exit codes", "Name and exit code rules" and "Unique service names" on all four targets
- [x] 2.6 Add the sealed trait `IntoServiceName` with implementations for `ServiceName` and `String`, and make `service` take `&IntoServiceName` and parse text at the step (design D17); verify the "Service name as text" scenario on all four targets

## 3. Pure phase engine and full hook order

Bead: lander-4us.5.3

- [x] 3.1 Add the private engine of design D6: `Engine::start` over the services, `Step`, `Action`, `ServiceRef` and `Pending` with `done` and `failed`; verify white-box table tests for the start order, the reverse stop order and skipped absent hooks on all four targets
- [x] 3.2 Add the started-service rule and failed-start handling; verify tests for a failure in `starting`, `start` and `started`
- [x] 3.3 Add stop-failure collection; verify that a failing `stop` does not skip the next hooks and makes the code 1, with the failures in `RunOutcome` (group 5 adds the standard-error report)
- [x] 3.4 Add a property test: for random service counts, hook sets and failure points, each started service gets each present stop hook exactly once, in reverse order, no step follows `Finish`, and a second reply to one token changes nothing
- [x] 3.5 Add the `stop_requested` and `timed_out` replies; verify table tests for a stop request during the start phase, during the command and during the stop phase, and a time-out that skips the other stop hooks, raises the stopped event and gives code 1
- [x] 3.6 Give `service` all six hooks and move `@hosting.run` onto the engine, with `done` for each `Raise` action until group 4; verify that the group 2 tests still pass and that `run` gives the hook orders of the spec on native and js

## 4. Lifetime, stop requests and cancellation checks

Bead: lander-4us.5.4

- [x] 4.1 Add `Lifetime` with `on_started`, `on_stopping`, `on_stopped`, late registration and `stop_reason`; verify tests for event order and late handlers
- [x] 4.2 Add `stop_application(exit_code?)`, `set_exit_code`, `StopToken`, `ctx.cancelled()`, `ctx.check_cancelled()` and `StopRequested`, with registered stop probes; verify tests for a stop from the command, from a hook during start, and repeated requests
- [x] 4.3 Treat a `StopRequested` raised by the command as a stop, not a failure; verify the exit code is not 1
- [x] 4.4 Cancel the command task on a stop request (native, js); verify that a command in `@async.sleep` ends with cancellation and that its `defer` block runs before the stop phase
- [x] 4.5 Verify that a stop hook sees the changes that the command made in `S`
- [x] 4.6 Document the lifetime, the cancellation checks, and the `@async.pause()` rule for long synchronous loops on js in the package README

## 5. Exit codes and error reports

Bead: lander-4us.5.5

- [x] 5.1 Add `ExitCode`, `UsageError` and the precedence function as a pure function; verify a table test of all precedence pairs, with 130, 143 and 131
- [x] 5.2 Map `ConfigError` and `UsageError` to 2 and other errors to 1; verify tests with a configuration error before start and a binding error in the command
- [x] 5.3 Add the default standard-error report and `@hosting.error_report`; verify the report text and that a custom report replaces it

## 6. Arguments first and standard flags

Bead: lander-4us.5.6

- [x] 6.1 Create `moonrockz/moon-lander-hosting/argparse` with `command(make, mappings?)`; make `run` parse `args` one time before any file read and put the result in `Context[S].args`; verify that an unknown option gives `UsageError` with the argparse message and code 2, and that no file read and no hook occur
- [x] 6.2 Parse with an empty command named after the application when no `command` step exists; verify an extra argument gives code 2
- [x] 6.3 Add `environment_option`, `config_option`, `isolated_flag` and `project_option`, and fill `DiscoveryOptions` (`environment`, `config`, `isolated`, `project`); verify one test per flag and that no flag value becomes a configuration key
- [x] 6.4 Give a `UsageError` for an empty `--environment`, `--config` or `--project` value; verify code 2 and no hook run
- [x] 6.5 Verify that `--environment Staging` after a subcommand is accepted

## 7. Application name, prefix and environment-variable source

Bead: lander-4us.5.7

- [x] 7.1 Derive the prefix from the application name (upper case, `-` to `_`) and add `@hosting.env_prefix`; verify the default and the override
- [x] 7.2 Compose the core environment-variable source at priority 600 with reserved `<PREFIX>_ENVIRONMENT`, `<PREFIX>_HOME` and `@hosting.reserve_env` names; verify that reserved names do not become keys and the source report shows 600
- [x] 7.3 Add `@hosting.env_vars(vars)`, which replaces the variable set of the run, and `@hosting.skip_env_source()`, which skips only the `<PREFIX>_*` source (design D12); verify the "A later env_vars step replaces the set" scenario and a skipped source report on all four targets
- [x] 7.4 Add `@hosting.app_dirs()`, which gives the application name and the prefix to `@conventions.app_dirs`; verify `$<PREFIX>_HOME` and the variable source use one prefix
- [x] 7.5 Add the starting settings `env_vars?`, `working_dir?` and `environment?` to `@lander.cli` and `@hosting.builder`, `@hosting.working_dir(path)`, and run step 2 that fills only omitted values from `moonbitlang/core/env` on native and js (empty set and `/` on wasm and wasm-gc) and gives both values to the core builder; verify the three "Host starting settings" scenarios, "A later working_dir step", "Every reader sees one set" and "Starting environment is the default"
- [x] 7.6 Add the trait `IntoEnvVars` with implementations for `Map[String, String]` and `Json` and the JSON rules of design D14; verify the "Map literal", "JSON fixture", "Mixed values", "Null value" and "Root that is not an object" scenarios on all four targets
- [x] 7.7 Add `EnvPrefix::parse` and the default prefix from an `AppName`, which cannot fail (design D17); make `@hosting.env_prefix` take an `EnvPrefix`; verify each rule on both sides of its limit on all four targets
- [x] 7.8 Use a path type for the working directory of the run in place of `String` (design D17); verify that an empty or relative path does not parse, on all four targets

## 8. Host environment

Bead: lander-4us.5.8

- [x] 8.1 Add `HostEnvironment` with `is_environment`, `is_development`, `is_staging`, `is_production`; verify tests with `None` and with mixed-case names
- [x] 8.2 Resolve the name from `--environment`, `<PREFIX>_ENVIRONMENT` and `default_environment`, and check it with the conventions name rules; verify the resolution-order tests and that an invalid name gives code 2 with no hook run
- [x] 8.3 Make `@hosting.default_environment` also enable environment files; verify that the default enables environment files and the resolved name reaches the conventions input in a composition test
- [x] 8.4 Set the content root (builder value, else the working directory of the run) with `/` separators; verify one test per target group and one Windows test
- [x] 8.5 Use a parsed environment-name type in `HostEnvironment`, `default_environment` and the starting setting `environment?` in place of `String` (design D17); verify that a name that breaks the conventions name rules cannot make a value

## 9. Configuration load and services factory

Bead: lander-4us.5.9

- [ ] 9.1 Add `@hosting.configure` over the `ConfigBuilder` pipeline, and the builder trait if core gives one; verify an example with `|> @conventions.add(@conventions.app_dirs("acme"))`
- [ ] 9.2 Load through `@host.load(builder)` on native and js; verify the factory reads a merged value
- [ ] 9.3 Add `@hosting.files(tree)` and load through `@config.load(builder, tree)` on wasm and wasm-gc; verify a complete tree and an incomplete tree (code 2, requested paths on standard error)
- [ ] 9.4 Add `BuildContext` and `Context[S]` with `config`, `env_vars` and `working_dir`; verify that the factory runs one time and that hooks and the command get the same `S`, `env_vars` and `working_dir`
- [ ] 9.5 Add `@hosting.shutdown_timeout_key(key : @config.KeyPath)` (design D6), read one time after the configuration load and before the factory through `FromConfig` for `TimeLimit`; verify the scenarios of "Shutdown timeout from a named key" on native and js
- [ ] 9.6 Verify an acceptance test in `tests/` where `--project` selects a member by path before name, and an ambiguous name gives code 2, through the configuration load

- [ ] 9.7 Verify an acceptance test in `tests/` where `acme.Staging.toml` loads with `--environment Staging`, through the configuration load

## 10. Shutdown timeout

Bead: lander-4us.5.10

- [x] 10.1 Add `@hosting.shutdown_timeout(limit : TimeLimit)` (default `TimeLimit::seconds(30)`) and the bounded stop phase inside `protect_from_cancel`; verify on native and js that a slow `stop` is cancelled, later hooks are skipped, the stopped event occurs and the code is 1
- [x] 10.2 Verify that a stop phase after an outside cancel still runs all hooks and keeps its timeout
- [x] 10.3 Verify that the builder takes a `TimeLimit` from `moonrockz/moon-lander-core` and that the default is `TimeLimit::seconds(30)` (design D17); a negative or zero limit cannot exist, because `TimeLimit` rejects it

## 11. Console driver on native with the C stub

Bead: lander-4us.5.11

- [ ] 11.1 Create `moonrockz/moon-lander-hosting/console` `run` for native over the spike stub: install handlers, register the flag as a stop probe, run a 50 ms watcher task that calls `stop_application` with `Signal(kind)`, and end the process with libc `exit(code)`
- [ ] 11.2 Add a test program in `tests/` and native acceptance tests that send SIGINT, SIGTERM and SIGQUIT on Linux and macOS; verify codes 130, 143 and 131, the exact `SignalKind`, no core dump, and all stop hooks
- [ ] 11.3 Add Windows acceptance tests that send each console event that task 1.2 found a CI runner can send to one child process (`CTRL_BREAK_EVENT` at least); verify its code (131 for `CTRL_BREAK_EVENT`) and the stop hooks. For each event that task 1.2 recorded as not sendable from a program (`CTRL_CLOSE_EVENT`, and `CTRL_C_EVENT` to one process group), verify the mapping and the code through a unit test of the handler logic, and record the manual check in the package README
- [ ] 11.4 Verify that a second SIGINT during a slow stop hook ends the process at once with 130 and skips the remaining hooks
- [ ] 11.5 Verify that a synchronous loop that polls `ctx.cancelled()` sees the first signal, and that a loop with no check ends at the second signal
- [ ] 11.6 Document the Windows console-close time limit in the package README

## 12. Console driver on js

Bead: lander-4us.5.12

- [ ] 12.1 Create the hosting node adapter `pkgs/hosting/adapters/node` as a second entry point of `build-node-adapter.mbtx` (AGENTS.md already allows it); add the signal functions to it (`process.on` for SIGINT, SIGTERM, SIGQUIT on POSIX; SIGINT, SIGBREAK, SIGHUP on Windows), and the MoonBit js externs that call them
- [ ] 12.2 Set `process.exitCode`, remove the listeners at the end, and call `process.exit(code)` on a second signal
- [ ] 12.3 Add js acceptance tests that run the test program under the pinned Node.js and send signals; verify codes 130, 143 and 131, the full stop phase, and a second signal that exits at once, on Linux, macOS and Windows
- [ ] 12.4 Verify that the bundle also runs the test program under Bun
- [ ] 12.5 Verify that piped standard output is complete after a clean run and after a graceful signal stop

## 13. Embedded driver on wasm and wasm-gc

Bead: lander-4us.5.13

- [ ] 13.1 Add `@hosting.run_embedded(command, stop_probe?)` that runs the engine and each hook through the `%async.run` intrinsic in one per-target file; verify a clean run and a failing command on wasm and wasm-gc
- [ ] 13.2 Report a hook that suspends as a failure; verify the message and code 1
- [ ] 13.3 Register the embedder probe as a stop probe; verify a polling command that stops when the probe reports a stop

## 14. argparse overrides layer

Bead: lander-4us.5.14

- [ ] 14.1 Add `map` and `to_overrides` with value types and parse functions, and put the overrides source last at priority 700; verify flag, count, single, append and default-source cases on all four targets
- [ ] 14.2 Verify an acceptance test in `tests/` where `--log-format json` beats a file value and a variable, the origin kind is `overrides`, and the report shows priority 700
- [ ] 14.3 Document the adapter with the pipeline example from design.md D2 as a compiled doc test

## 15. Integration check with the Morphir shape

Bead: lander-4us.5.15

- [ ] 15.1 Add an acceptance test in `tests/` that builds a Morphir-like host on the bare `@hosting.builder` (conventions preset, prefix `MORPHIR`, reserved `MORPHIR_LOG_DIR`, standard flags, telemetry `stopping` flush, argparse overrides) and verify exit codes 0, 1, 2 and 130 and one flush per run
- [ ] 15.2 Run `mise run check` and `mise run test:native-zig`; verify both pass

## 16. Batteries-included @lander defaults

Bead: lander-4us.5.16

- [ ] 16.1 Add the bare entry `@hosting.builder(name, args, env_vars?, working_dir?, environment?)`, and make `@lander.cli` give `HostBuilder[Unit]` with the defaults of design D15 on: the formats from `moonrockz/moon-lander-config/formats`, `app_dirs(name, prefix~)`, the standard flags and environment-file discovery; verify the "Smallest program" and "Bare builder" scenarios and the two "Environment files under the batteries entry" scenarios
- [ ] 16.2 Add `@lander.formats`, `@lander.conventions`, `@lander.no_standard_flags` and `@lander.no_environments`, add the standard flags to the root argparse command without duplicates, and add the `pub using` re-exports of D15; verify the five "Change or turn off a default" scenarios and that `moon info` lists the re-exports in the `@lander` interface
- [ ] 16.3 Add `@lander.build(factory)`, which changes `HostBuilder[Unit]` to `HostBuilder[S]` and keeps earlier settings and hosted services; verify the "No build step" and "Build after other steps" scenarios on all four targets
- [ ] 16.4 Add `@lander.run(command)` as a synchronous function with one file per target group: the console driver on native and js, the embedded driver on wasm and wasm-gc; verify that one `fn main` source builds on all four targets and the two "Driver selection by target" scenarios. If the native or js call to the `moonbitlang/async` entry fails, use the fallback in D15 and tell the owner
- [ ] 16.5 Add the smallest program as a doc test in `pkgs/lander/README.mbt.md`, and write every batteries example in the README in the one `@lander` style of D15; verify that `mise run test` compiles the examples
- [ ] 16.6 Add acceptance tests in `tests/` for "No file present", "Empty file", "One-key partial file" and "Partial user override", with the show and explain helper output and the origin kind `defaults`; verify them on native, js and wasm-gc (with an injected tree)
- [ ] 16.7 Add the `Program` trait and `run_app(factory)` in `@hosting`, re-export both from `@lander` with `pub using`; verify the "Services record runs as the program" and "Same result as the lambda form" scenarios on all four targets
- [ ] 16.8 Run `mise run check` and `mise run test:native-zig`; verify both pass

## Workflow follow-up

- If the C stub spike in group 1 fails, record the failure in the bead and tell the owner.
- Archive the change after review.
