# Design: Add the host lifecycle

Labels: "Owner" marks a decision of the project owner. "Call" marks a designer
decision that the owner did not reject. "Call (this change)" marks a decision that
this change adds. The owner can change a Call without a change to the Owner decisions.
Items O1 to O3 and R1 to R12 come from the reconciliation addendum of 2026-10-20.
They replace earlier text where the two disagree. "Owner (2026-10-20)" marks the
later owner decisions on host starting settings (D13), the `IntoEnvVars` input (D14),
and the local override layer of `configuration-conventions`.

## Context

See proposal.md (Why). This section gives only the facts that shape the design.

- Moon-Lander has no host today. `pkgs/lander` exports only `version()`.
- This change depends on `add-configuration-core` (`ConfigBuilder`, sources, the
  overrides source, `FileTree`, `LoadStep`, `@config.load`, `@config/host.load`,
  `Config`, `ConfigError`), `add-configuration-conventions` (`@conventions.add`,
  `@conventions.app_dirs`, `@conventions.environments`, `DiscoveryOptions`, the
  environment name rules) and `add-configuration-binding` (`bind`, `Options[T]`). This
  design uses their shared names. It does not specify their behavior.
- finos/morphir-moonbit (commit 32ab9d7) does these things that the host must replace:
  - `apps/morphir/main.mbt` uses a synchronous `fn main`. It catches all errors and
    maps them by a string compare: `if message == "Cancelled" { 130 } else { 2 }`.
    `run_content` failures give 1 by the same compare. It calls `@platform.exit`.
  - `pkgs/morphir-host/platform/platform.c` installs a SIGINT `sigaction` handler for
    each command (`interruption_start`/`interruption_stop`). The handler only sets a
    `volatile sig_atomic_t` flag. Synchronous code polls `interruption_requested()`.
    It also forwards SIGINT to an owned child process.
  - `platform/js.mbt`: a launcher owns SIGINT and sets a shared `Atomics` flag. The
    synchronous evaluator runs in a worker thread and polls the flag.
  - `platform/gc.mbt` (wasm-gc) asks the embedder through `call("interruption_requested")`.
    `interruption.mbt` gives `false` on wasm.
  - `--cancel-file` is a second, file-based stop request for embedders and tests.
  - `observability.mbt`: `TelemetrySession::flush` runs from `defer logs.flush()`.
    The flush has its own deadline (1 to 5000 ms).

### Platform findings

Sources: `moonbitlang/async` 0.22.5 (source read from the registry cache, and a probe
module built in a scratch directory with the pinned toolchain `moonc v0.10.15`), and
`moonbitlang/core/argparse` from the same toolchain.

| Capability | native | js | wasm | wasm-gc |
| --- | --- | --- | --- | --- |
| `async fn main`, task groups | Yes | Yes (Node.js event loop) | Only when the embedder supplies the `moonbitlang/async` imports. `moonrun` does. A plain WASI runtime does not. | No. The build fails: "Value run_async_main not found in package `moonbitlang/async`". Async tests do not run ("no test entry found"). |
| `sleep`, `with_timeout` | Yes | Yes | Embedder imports | No. `sleep` aborts ("unimplemented on WASM backend"). |
| `moonbitlang/async/signal` | SIGINT, SIGTERM, SIGHUP on Unix. Ctrl-C, close and break events on Windows. | No. "This package currently does not support JavaScript backend". | Compiles. Needs embedder imports. | No |
| SIGQUIT in `moonbitlang/async` | No. The `Signal` enum has only SIGINT, SIGTERM, SIGHUP, SIGBREAK. | Not applicable (Node.js `process.on("SIGQUIT")` works on POSIX) | No | No |
| Custom handler in `moonbitlang/async` | No. The README lists "custom signal handling logic" as not done. A signal only cancels the main task. | Not applicable (Node.js listeners) | No | No |
| Which signal arrived, from `moonbitlang/async` | Not public. `KilledBySignal(Int)` is in an internal package. | Not applicable (the listener gets the name) | No | No |
| `protect_from_cancel` with `with_timeout_opt` inside | Works. Probe: a stop block after an outside cancel ran, and its 30 ms timeout ended a 1 s hook. | Works (same probe) | Not tested | Not available |
| `is_being_cancelled()` | `true` before `protect_from_cancel`, `false` inside it (probe) | Same | Not tested | Not available |
| `%async.run` intrinsic | Not needed | Not needed | Runs an async closure up to its first suspension | Same. Probe: two async hooks that do not suspend ran to the end. |
| `argparse` `--help`, `--version` | Calls libc `exit(0)` | `process.exit(0)` | WASI `proc_exit` | `__moonbit_sys_unstable` `exit` |
| `argparse` error types | `ArgError`, `ArgParseError` and `DisplayHelp` are private. Only the message is public. | Same | Same | Same |
| `argparse` `Matches.sources` | `Argv`, `Env` or `Default` for each value | Same | Same | Same |

The async runtime is cooperative and single-threaded. On native, the runtime reads
its own signal pipe only at a suspension point. On js, a Node.js listener runs only
when the JavaScript stack is empty. Because `moonbitlang/async` gives no SIGQUIT, no
signal identity and no handler that runs during synchronous code, the owner allows a
native signal stub in Zig (O1, D7).

### Platform limits that remain

1. **Signals on wasm and wasm-gc.** Not possible (Call). The lifetime stops through
   `stop_application` or an embedder probe.
2. **Shutdown timeout on wasm and wasm-gc.** Not possible without timers. Hooks on
   these targets must not suspend, so they cannot wait.
3. **Synchronous code that does not yield on js.** A Node.js listener does not run
   while a synchronous computation holds the stack. `ctx.cancelled()` cannot see the
   signal, and a second signal has no effect, until the code yields. Morphir keeps its
   worker-thread model on js. The native Zig stub removes this limit on native (D7).
4. **Windows close event.** After `CTRL_CLOSE_EVENT`, Windows ends the process when
   the handler returns or when the system time limit ends (about 5 seconds). The stop
   phase after a console close must end inside that limit. The host cannot extend it.
5. **Feasibility of the Zig stub is not verified (O1).** Task group 1 is a spike. Owner: consumers get prebuilt stub objects. The package ships one prebuilt Zig object or static library for each native platform, so a consumer needs no Zig toolchain. If prebuilt objects are too complex to ship or link, the stub is written in C as a normal `native-stub`, which the consumer's C compiler builds.

## Goals / Non-Goals

**Goals:**

- One host model on all four targets. Only the drivers differ per target.
- Linux, macOS and Windows are targets for native and js (O3).
- A pure, synchronous phase engine that tests can step through on all four targets.
- A pipeline API that uses MoonBit features: `|>`, labelled and optional arguments,
  enums, `suberror`, `async fn`, `defer`, and per-target files.
- Let finos/morphir-moonbit remove its own interruption and exit-code code.

**Non-Goals:**

- No `BackgroundService` equivalent. A `start` hook must return. Long-running work is
  the command.
- No concurrent service start (.NET `ServicesStartConcurrently`).
- No shutdown timeout from configuration keys. Only the builder sets it.
- No custom error-to-exit-code classifier. The application sets a code instead.

## Decisions

### D1. Typed host, no container (Owner: no DI container; Call: `Host[S]`, `Context[S]`)

The application defines a services record `S`. The host builds it one time with a
factory. `HostBuilder[S]` is generic from the start. The factory fixes `S` through
type inference.

```moonbit
pub struct Context[S] {
  services : S
  config : @config.Config
  environment : HostEnvironment
  lifetime : Lifetime
  args : @argparse.Matches
  env_vars : Map[String, String]   // the one variable set of the run (D13)
  working_dir : String             // the one working directory of the run (D13)
}
```

- Call (this change): the factory gets a `BuildContext` (configuration, environment,
  parsed arguments, `env_vars` and `working_dir`), not `Context[S]`, because `S` does
  not exist yet.
- Call (this change): `Context[S]` is immutable. Mutable state lives in the
  services that `S` holds. The stop phase gets the same `Context[S]` value. This fixes
  the starbase fault where shutdown saw a copy of the session.
- Call (this change): `args` holds the one argparse result of the run (R7). The
  command reads its subcommand and options from it.
- Alternative: a trait-object registry. Rejected by the owner for now.

### D2. Builder pipeline (Owner: pipelines; Call (this change): API shape; R1, R7, R8)

`build` does no I/O. It returns `Host[S]`. The run function parses the arguments,
loads the configuration, builds `S`, and runs the phases. So the same `Host[S]` value
works with each driver.

```moonbit
async fn main {
  @lander.cli("morphir", @env.args())
  |> @hosting_argparse.command(fn(name) {
    @argparse.Command(name,
      options=[
        @hosting_argparse.environment_option(),
        @hosting_argparse.config_option(),
        @hosting_argparse.project_option(),
        @argparse.OptionArg("log-format", long="log-format"),
      ],
      flags=[
        @hosting_argparse.isolated_flag(),
        @argparse.FlagArg("verbose", short='v', action=Count),
      ],
      subcommands=[build_command, workspace_command],
    )
  }, mappings=[
    @hosting_argparse.map("log-format", "log.format"),
    @hosting_argparse.map("verbose", "log.verbosity"),
  ])
  |> @hosting.configure(fn(sources) {
    sources
    |> @config.defaults(Defaults::default())
  })
  |> @hosting.app_dirs()   // = @conventions.add(@conventions.app_dirs(name, prefix~)) with host values
  |> @hosting.reserve_env(["MORPHIR_LOG_DIR"])
  |> @hosting.service("telemetry", stopping=fn(ctx) { ctx.services.logs.flush() })
  |> @hosting.shutdown_timeout(5_000)
  |> @hosting.build(fn(b) {
    App::{ logs: TelemetrySession::local(b.environment.content_root, ...), ... }
  })
  |> @hosting_console.run(fn(ctx) { morphir_command(ctx) })
}

async fn morphir_command(ctx : @hosting.Context[App]) -> Unit raise {
  let ir : IrOptions = ctx.config |> @config.bind("ir")
  for item in work_items(ctx) {
    ctx.check_cancelled() // a cheap read; raises StopRequested after a stop request
    process(item)
  }
  if has_errors(ctx) {
    ctx.lifetime.set_exit_code(@hosting.ExitCode(2))
  }
}
```

- Call (R8): the application name occurs one time, in `@lander.cli(name, args)`.
  `@lander.cli` calls `@hosting.builder`. The argparse command gets the name through
  the `fn(name)` argument.
- Call (R8): the variable prefix defaults to the application name in upper case, with
  `-` changed to `_`. `|> @hosting.env_prefix("...")` changes it.
- Call (R8): the host composes the environment-variable source itself (D12). The
  application does not add `@config.env`.
- Call (R1, R8): `@conventions.app_dirs(name, prefix?, display?)` keeps a required name,
  so it works without a host. Inside a host, `|> @hosting.app_dirs()` adds
  `@conventions.add(@conventions.app_dirs(name, prefix~))` with the name from
  `@lander.cli` and the host prefix. The application gives the name one time.
- Call (this change): `@hosting.configure(fn(sources) { ... })` takes the
  `ConfigBuilder` pipeline of `configuration-core`. If core gives a builder trait,
  `HostBuilder[S]` implements it, and the direct form `|> @config.defaults(...)` also
  works.
- Call (R1): on wasm and wasm-gc, the application gives the file snapshot with
  `|> @hosting.files(tree)`. On native and js, the host reads files itself.
- Owner (2026-10-20): the variable set and the working directory of the run are
  host starting settings (D13). The application gives them to `@lander.cli` or with
  later steps. Each omitted value comes from the process on native and js.

### D3. Run order (Owner: .NET model; Call (R7): argparse runs first)

1. The host parses `args` one time with `moonbitlang/core/argparse`. An argparse
   error or a misused standard flag ends the run with `UsageError` and exit code 2,
   before any file read. `--help` and `--version` end the process inside argparse with
   code 0.
2. The host fixes the variable set and the working directory of the run (D13). It
   converts a given `IntoEnvVars` value (D14), and fills each omitted value from the
   process on native and js. A conversion error ends the run with `UsageError` and
   exit code 2, before any file read. The host gives both values to the core builder
   (`@config.env_vars`, `@config.working_dir`).
3. The host finds the environment name for `HostEnvironment`: the `--environment`
   value, then `<PREFIX>_ENVIRONMENT` in the variable set of the run, then the builder
   default. This is the same order that conventions uses, so both give the same name.
   It checks the name with the name rules of `configuration-conventions`. A bad name
   raises `ConfigError::InvalidEnvironmentName` (exit code 2).
4. The host makes `DiscoveryOptions` (`environment`, `config`, `isolated`, `project`)
   from the standard flags (D10), and gives it to the conventions parts.
5. The host loads the configuration. Native and js: `@config/host.load(builder)`.
   wasm and wasm-gc: `@config.load(builder, tree)` with the tree from
   `@hosting.files`. The merge order is the application sources, then the
   environment variables (priority 600), then the argparse overrides (priority 700).
   A `ConfigError` ends the run with exit code 2 before any hook.
6. The host makes `HostEnvironment` and the factory builds `S`.
7. Start phase, started event, command, stop phase, exit.

- Call (R7): conventions never reads `argv`. It gets the flag values only through
  `DiscoveryOptions`. The conventions bootstrap read of raw arguments is not used.
- Call (this change): on wasm and wasm-gc, a `Need(...)` result from
  `@config.load` means the injected tree is not complete. The host ends the run with
  exit code 2 and reports the requested paths. A complete tree never gives `Need` (R1).

### D4. Hosted services as values (Owner: .NET hooks; Call (this change): shape)

A service is a value with a name and six optional hooks, not a trait.

```moonbit
pub(all) struct HostedService[S] {
  name : String
  starting : Hook[S]?
  start : Hook[S]?
  started : Hook[S]?
  stopping : Hook[S]?
  stop : Hook[S]?
  stopped : Hook[S]?
}
pub type Hook[S] = async (Context[S]) -> Unit raise

pub fn[S] service(
  self : HostBuilder[S], name : String,
  starting? : Hook[S], start? : Hook[S], started? : Hook[S],
  stopping? : Hook[S], stop? : Hook[S], stopped? : Hook[S],
) -> HostBuilder[S]
```

- Owner: start in registration order, stop in reverse. .NET 8 order: all `starting`,
  then all `start`, then all `started`. Stop: all `stopping`, all `stop`, all
  `stopped`, each in reverse.
- Call (this change): a service is started when its `start` hook succeeds (or it has
  no `start` hook and its `starting` hook did not fail). Only started services get stop
  hooks.
- Call (this change): a stop hook failure does not skip the next hooks. The host
  collects all failures.
- Stop hooks read the reason with `ctx.lifetime.stop_reason()`.

### D5. Lifetime, stop requests and cancellation checks (Owner: .NET `IHostApplicationLifetime`; O1)

```moonbit
pub fn Lifetime::on_started(self : Lifetime, handler : () -> Unit) -> Unit
pub fn Lifetime::on_stopping(self : Lifetime, handler : () -> Unit) -> Unit
pub fn Lifetime::on_stopped(self : Lifetime, handler : () -> Unit) -> Unit
pub fn Lifetime::stop_application(self : Lifetime, exit_code? : ExitCode) -> Unit
pub fn Lifetime::set_exit_code(self : Lifetime, code : ExitCode) -> Unit
pub fn Lifetime::stop_reason(self : Lifetime) -> StopReason?
pub fn Lifetime::stop_token(self : Lifetime) -> StopToken
pub fn StopToken::cancelled(self : StopToken) -> Bool
pub fn StopToken::check_cancelled(self : StopToken) -> Unit raise StopRequested
pub fn[S] Context::cancelled(self : Context[S]) -> Bool
pub fn[S] Context::check_cancelled(self : Context[S]) -> Unit raise StopRequested
pub(all) suberror StopRequested

pub(all) enum StopReason {
  Completed            // the command returned
  Requested            // stop_application
  Signal(SignalKind)
  Embedder             // the embedder probe
  StartFailed(Error)
  Failed(Error)        // the command raised
}
pub(all) enum SignalKind { Interrupt; Terminate; Quit }
```

- Owner (O1): `ctx.cancelled()` and `ctx.check_cancelled()` are cheap reads that
  synchronous code can poll. They give `true` (or raise) after a stop request, when a
  registered stop probe reports a stop (the native signal flag, D7, or the embedder
  probe, D6), or when `@async.is_being_cancelled()` is true (native and js).
- Owner (O1): `SignalKind` has no `Unknown` value. The console driver knows which
  signal arrived on every platform (D7).
- Call (this change): `StopToken` holds the same check for code that does not get
  `Context[S]`, for example an evaluator.
- Call (this change): when the command raises `StopRequested`, the host treats it as
  a normal stop, not as a failure. The stop reason stays the reason of the first
  request.
- Call (this change): event handlers are synchronous and cannot raise. A handler
  that is registered after its event runs at once (like .NET token registration).
- Call (this change): the first stop request sets the reason. Later requests have no
  effect, except that a signal still sets the signal exit code.
- Call (this change): on native and js, a stop request also cancels the command task.
  The command stops at its next suspension point and its `defer` blocks run. A command
  protects a critical part with `@async.protect_from_cancel`.
- Call (this change): a stop request during the start phase lets the current hook
  end, skips the other start hooks and the command, and stops the started services.

### D6. Pure phase engine and drivers (Call: pure engine; Call (this change): drivers)

The engine is a state machine over explicit inputs. It has no I/O and no async code.

```moonbit
pub(all) enum Step {
  Starting(Int); Start(Int); Started(Int); RaiseStarted; RunCommand
  RaiseStopping; Stopping(Int); Stop(Int); Stopped(Int); RaiseStopped
  Finish(ExitCode)
}
pub(all) enum Input {
  Done; HookFailed(Error); StopRequested(StopReason, ExitCode?); TimedOut
}
pub fn Engine::new(service_count : Int, hooks : HookMask) -> Engine
pub fn Engine::next(self : Engine, input : Input) -> (Engine, Step)
```

Drivers run the steps:

| Driver | Targets | How it runs hooks | Timeout | Stop sources |
| --- | --- | --- | --- | --- |
| `@hosting.run` (async) | native, js | `with_task_group`; the command in a child task | `with_timeout_opt` inside `protect_from_cancel` | `stop_application`, outside cancel |
| `@hosting_console.run` | native, js | `@hosting.run` plus signals and process exit | Same | Above plus signals |
| `@hosting.run_embedded` | wasm, wasm-gc | `%async.run` per hook; a hook that suspends is a failure | None | `stop_application`, embedder probe |

- Call (this change): `@hosting.run` returns a `RunOutcome` (exit code, reason,
  failures) and does not end the process. Tests use it.
- Call (this change): the stop phase runs inside `protect_from_cancel`. The driver
  reads `is_being_cancelled()` before it enters that block (the probe shows it is
  `false` inside).
- Call (this change): wasm uses the embedded driver too, so a WASI runtime without the
  `moonbitlang/async` imports can run the host.
- Call (this change): the shutdown timeout is one budget for the full stop phase. It
  starts when the command task has ended. Default 30 000 ms, as in .NET.

### D7. Console driver (Owner: SIGINT, SIGTERM, SIGQUIT give a graceful stop; Owner: O1, O2, O3)

The console driver is in `hosting/console`. It has one native part and one js part.

**Native: a Zig signal stub (Owner, O1).** The stub is Zig source in
`hosting/console`, built with the pinned `zig` 0.17.0 into a C-ABI object or static
library by a moonx task script, and linked through `moon.pkg` (`native-stub` or link
flags). MoonBit calls it through `extern "c"`. `moonbitlang/async` stays for all other
async work.

- Linux and macOS: the stub installs `sigaction` handlers for SIGINT, SIGTERM and
  SIGQUIT. SIGHUP keeps its default action, as in .NET `ConsoleLifetime` (Call).
- Windows: the stub calls `SetConsoleCtrlHandler` for `CTRL_C_EVENT`,
  `CTRL_BREAK_EVENT` and `CTRL_CLOSE_EVENT`.
- Mapping (Call, O3): SIGINT and `CTRL_C_EVENT` give `Interrupt`; SIGTERM and
  `CTRL_CLOSE_EVENT` give `Terminate`; SIGQUIT and `CTRL_BREAK_EVENT` give `Quit`.
- First signal: the handler stores the signal identity and sets an atomic stop flag.
  It does only async-signal-safe work.
- Second signal: the handler ends the process at once from inside the handler, with
  the exit code of the second signal (`_exit` on Linux and macOS, `ExitProcess` on
  Windows). This works while the command runs synchronous code that never yields.
- `ctx.cancelled()` reads the atomic flag through one extern call (D5). Synchronous
  code sees the first signal at its next check.
- Call (this change): a watcher task polls the flag every 50 ms with `@async.sleep`.
  When the flag is set, it calls `stop_application` with `Signal(kind)`. That cancels
  the command task at its next suspension point.
- Call (this change): the driver makes sure that the `moonbitlang/async` runtime does
  not also handle these signals. The spike checks how (for example
  `set_global_cancellation_signals([])`).
- Call (this change): on `CTRL_CLOSE_EVENT` the handler waits until the process ends,
  so Windows does not end the process before the stop phase. The system time limit
  still applies (Platform limits, item 4).
- After the stop phase, the driver ends the process explicitly with the exit code
  (D8) through libc `exit`, which flushes standard output.

**js: the TypeScript adapter (Owner, O2).** The js console lifetime lives in the
TypeScript adapter that the `config/host` js story adds. That adapter uses only
`node:*` APIs and is bundled with Bun. MoonBit js externs call it.

- The adapter installs `process.on` listeners. Linux and macOS: SIGINT, SIGTERM,
  SIGQUIT. Windows: SIGINT (Ctrl-C), SIGBREAK (Ctrl-Break) and SIGHUP (console close),
  which Node.js gives for the Windows console events. Call (this change): the mapping
  is the same as native: SIGBREAK gives `Quit`, SIGHUP on Windows gives `Terminate`.
- The first signal calls `stop_application` with `Signal(kind)`.
- A second signal calls `process.exit(code)` at once with the code of that signal.
- At the end, the driver removes the listeners and sets `process.exitCode` to the
  exit code. It does not call `process.exit` on a graceful stop, because that can drop
  output that is still in a pipe.
- Synchronous code that does not yield cannot see a signal on js (Platform limits,
  item 3).

### D8. Exit codes (Owner: 130, 143; Call: 1 and 2 match morphir-moonbit; Call (O3): 131 and explicit codes)

```moonbit
pub(all) struct ExitCode(Int) derive(Eq, Show)
```

| Code | Cause |
| --- | --- |
| 0 | Clean run |
| 1 | Unhandled failure in a hook or the command, stop failure, shutdown timeout |
| 2 | `ConfigError` (core, conventions, binding), `@hosting.UsageError`, incomplete injected tree |
| 130 | SIGINT or `CTRL_C_EVENT` stop |
| 143 | SIGTERM or `CTRL_CLOSE_EVENT` stop |
| 131 | SIGQUIT or `CTRL_BREAK_EVENT` stop |
| n | `set_exit_code` or `stop_application(exit_code=n)` |

- Call (O3): after a graceful signal stop, the host ends the process explicitly with
  130, 143 or 131 on every platform, including Windows. It does not raise the signal
  again, and Windows does not report `STATUS_CONTROL_C_EXIT`.
- Call (this change): precedence is signal, then 2, then 1 (failure), then 1 (stop
  failure or timeout), then the application code, then 0.
- Call (this change): the console driver writes the error message to standard error
  for codes 1 and 2. `@hosting.error_report(fn(err, code) { ... })` replaces it, so
  Morphir can keep its JSON error output.
- Call (R3): `@hosting.UsageError(String)` is a public `suberror` in hosting for CLI
  misuse, for example an argparse error or an empty `--environment` value. An
  application can raise it from its command. All configuration errors stay in the one
  core `ConfigError`.

### D9. Host environment (Owner: .NET style; Call: `Option` name, opt-in)

```moonbit
pub struct HostEnvironment {
  application_name : String
  environment_name : String?
  content_root : String
}
pub fn HostEnvironment::is_environment(self : HostEnvironment, name : String) -> Bool
pub fn HostEnvironment::is_development(self : HostEnvironment) -> Bool
pub fn HostEnvironment::is_staging(self : HostEnvironment) -> Bool
pub fn HostEnvironment::is_production(self : HostEnvironment) -> Bool
```

- Call: no default name.
- Call (R8): `|> @hosting.default_environment("Production")` sets the default and
  also enables environment files. `|> @conventions.environments()` enables the files
  without a default.
- Call (this change): the `is_*` checks compare without case, as .NET does. With no
  name, all give `false`. File matches stay exact (conventions).
- Call (this change): the content root is the builder value, else the working
  directory of the run (D13). On wasm and wasm-gc with no `working_dir`, that is `/`.
- Call (O3): the content root uses `/` as separator on every platform. The host
  converts a Windows working directory at the boundary.

### D10. argparse adapter and standard flags (Owner: argparse stays; Call (R7): standard flags; Call (R6): priority 700)

```moonbit
pub fn[S] command(b : HostBuilder[S], make : (String) -> @argparse.Command, mappings? : Array[Mapping]) -> HostBuilder[S]
pub fn environment_option() -> @argparse.OptionArg   // --environment <name>, global
pub fn config_option() -> @argparse.OptionArg        // --config <path>, global
pub fn isolated_flag() -> @argparse.FlagArg          // --isolated, global
pub fn project_option() -> @argparse.OptionArg       // --project <path|name>, global
pub fn map(option : String, key : String, parse? : (String) -> @config.ConfigValue raise) -> Mapping
pub fn to_overrides(matches : @argparse.Matches, mappings : Array[Mapping]) -> @config.ConfigSource
```

- Call (R7): the standard flags are opt-in. The application adds each one to its
  argparse command. The host knows them by their ids.
- Call (R7): the host fills the conventions `DiscoveryOptions` from the flags. A flag
  that is not given leaves its field at "not given".
  - `--environment <name>` sets `environment` and the host environment name (D3).
  - `--config <path>` sets `config` to `Explicit(path)` for the primary file.
  - `--isolated` sets `isolated`. Conventions then skips the system, global,
    local-override and user-override layers and keeps the environment variables, as
    in Morphir.
  - Call (this change, coordinator item): `--project <path|name>` sets `project`.
    Conventions selects the member with Morphir `--project` rules: a path match
    before a name match. An ambiguous name raises `ConfigError::AmbiguousProject`, and
    no match raises `ConfigError::UnknownProject` (exit code 2).
- Call (R3): an empty `--environment`, `--config` or `--project` value is a
  `UsageError`.
- Call (this change): with no `command` step, the host parses with an empty argparse
  command that has the application name. An extra argument is then a `UsageError`.
- Call (R6): the overrides source has priority 700. It is the last source in merge
  order.
- Call (this change): only mapped options go into the layer. This fixes the untyped
  CLI map in morphir-moonbit. The standard flags never go into the layer.
- Call (this change): values with `ValueSource::Default` stay out, so a file value is
  not hidden by an argparse default. Values from `Argv` and `Env` go in.
- Call (this change): a flag gives a boolean, a count flag an integer, a `Set` option a
  string, an `Append` option a list of strings. The mapping can give a parse function.
- Call (this change): the mapping applies to global options and to the options of the
  selected subcommand path. The application dispatches the subcommand itself.
- Call (this change): argparse errors are private types. The host wraps every parse
  error into `UsageError` with the argparse message.

### D11. Package layout (Call: shared names)

| Package | Targets | Contents |
| --- | --- | --- |
| `moonrockz/moon-lander/hosting` | all | Builder, `Host[S]`, `Context[S]`, engine, lifetime, environment, `ExitCode`, `UsageError`, `StopRequested`, `IntoEnvVars`, starting settings (`env_vars`, `working_dir`), env source composition, `run` (native, js), `run_embedded` (wasm, wasm-gc), `files` (wasm, wasm-gc) |
| `moonrockz/moon-lander/hosting/console` | native, js | Zig signal stub and native driver; js driver over the TypeScript adapter; process exit |
| `moonrockz/moon-lander/hosting/argparse` | all | `command`, standard flags, mappings, overrides source |
| `moonrockz/moon-lander` (`@lander`) | all | `cli` shortcut with the starting settings |

- `hosting` imports `config`, `config/conventions`, `config/host` (native and js) and
  `moonbitlang/core/argparse` (for `Context[S].args`).
- Call (O1): AGENTS.md gets a narrow exception: the native signal handlers in
  `hosting/console` use a Zig stub. All other process and filesystem work stays with
  `moonbitlang/async`. A task in this change makes that edit. The TypeScript exception
  belongs to the `config/host` js story (R12).

### D12. Environment-variable source (Call (R8), Call (R6))

- The host adds the environment-variable source of `configuration-core` with the
  prefix from D2, at priority 600, after the application sources and before the
  overrides.
- The reserved names always include `<PREFIX>_ENVIRONMENT` and `<PREFIX>_HOME`.
  `|> @hosting.reserve_env([...])` adds more names, for example `MORPHIR_LOG_DIR`.
- The source reads the one variable set of the run (D13). The bootstrap read of
  `<PREFIX>_ENVIRONMENT` and the conventions directory resolution read the same set.
- Call (this change): one API for the variable set. It keeps the three earlier
  selections:
  - `Process`: no step. The set is the one from `@lander.cli`, which is the process
    variables on native and js when `env_vars` is omitted, and empty on wasm.
  - `Explicit(vars)`: `|> @hosting.env_vars(vars)` with `vars : &IntoEnvVars`. It
    replaces the set for every reader, not only for this source.
  - `Skip`: `|> @hosting.skip_env_source()`. The `<PREFIX>_*` source loads nothing and
    reports `skipped`. The set stays for the bootstrap and the directories.
- `@conventions.app_dirs` gets the application name and the prefix from the host, so
  `$<PREFIX>_HOME` and the variable source use one prefix.

### D13. Host starting settings (Owner (2026-10-20): like .NET `HostApplicationBuilderSettings`)

```moonbit
pub fn[S] cli(
  name : String,
  args : Array[String],
  env_vars? : &@hosting.IntoEnvVars,
  working_dir? : String,
  environment? : String,
) -> @hosting.HostBuilder[S]

pub fn[S] env_vars(self : HostBuilder[S], vars : &IntoEnvVars) -> HostBuilder[S]
pub fn[S] working_dir(self : HostBuilder[S], path : String) -> HostBuilder[S]
```

- Owner: each run has one starting variable set and one working directory. Nothing
  reads the process environment or the process working directory, except where the
  host fills an omitted value.
- Owner: on native and js, an omitted `env_vars` or `working_dir` comes from the
  process through `moonbitlang/core/env`. Call: on wasm and wasm-gc, an omitted
  `env_vars` is the empty set and an omitted `working_dir` is `/`.
- Call (this change): the host fills omitted values one time, in run step 2 (D3), and
  only for values that no step gave. Explicit values therefore give no process read,
  and the same inputs give the same result on every target.
- Call: an explicit `environment?` is the builder default name, the same as
  `|> @hosting.default_environment(name)`, so it also enables environment files. The
  resolution order stays: `--environment`, then `<PREFIX>_ENVIRONMENT`, then the
  default.
- Owner: a later step can change the values before `build`.
  `|> @hosting.env_vars(vars)` replaces the set (D12). Call:
  `|> @hosting.working_dir(path)` replaces the working directory. The last step wins.
- Owner: the one set feeds the `<PREFIX>_*` environment source (600, D12), the
  environment-name bootstrap (D3), all directory resolution in conventions (`HOME`,
  `XDG_CONFIG_HOME`, `APPDATA`, `PROGRAMDATA`, `USERPROFILE`, `<PREFIX>_HOME`), and the
  core `config/host` adapter. The host gives the set and the directory to the core
  builder, so `config/host` reads nothing from the process. Walk-up discovery starts at
  the working directory.
- Owner: `BuildContext.env_vars`, `BuildContext.working_dir`, `Context[S].env_vars`
  and `Context[S].working_dir` show the values. `env_vars` is an immutable
  `Map[String, String]`: the host makes it one time and never changes it.
- Call (O3): the working directory uses `/` as the separator on every platform. The
  host converts a Windows process working directory at the boundary.

### D14. Variable set from a map or JSON (Owner idea; Call on shape, verified with a `moonc v0.10.15` probe)

```moonbit
pub trait IntoEnvVars {
  into_env_vars(Self) -> Map[String, String] raise
}
pub impl IntoEnvVars for Map[String, String]
pub impl IntoEnvVars for Json
```

The parameter type is `&IntoEnvVars`. Probe results:

- A brace literal with only string values, given to `&IntoEnvVars`, becomes a `Map`.
- A literal with mixed values needs `({ ... } : Json)`. Without it, the compiler
  reports "has type: Int, wanted: String".
- A `Json` value, for example a fixture from `@json.parse`, passes directly.
- An empty `{}` is ambiguous. Use `Map([])`.

```moonbit
@lander.cli("acme", ["build"], env_vars={ "HOME": "/home/test" }, working_dir="/w")
@lander.cli("acme", [], env_vars=({ "ACME_PORT": 8080, "ACME_DEBUG": true } : Json))
@lander.cli("acme", [], env_vars=fixture)   // fixture : Json from @json.parse
@lander.cli("acme", [], env_vars=Map([]))
```

JSON rules (Call):

- The root must be an object. Any other root raises `UsageError` (exit code 2).
- A string value stays as it is.
- A Boolean or a number becomes its JSON text, for example `true` and `1`.
- An array or an object becomes its JSON text. The core environment source parses a
  value that starts with `[` or `{` as JSON, so the value comes back the same.
- `null` means that the variable is not set.
- A nested object is not flattened into `__` names.
- Keys stay exactly as written.

### Mapping from .NET and starbase

| .NET | starbase 0.13.3 | Moon-Lander |
| --- | --- | --- |
| `Host.CreateApplicationBuilder(args)` | `App::default()` | `@lander.cli(name, args)` |
| `HostApplicationBuilderSettings` | (none) | Optional labelled arguments of `@lander.cli` (`env_vars?`, `working_dir?`, `environment?`) |
| `builder.Configuration.Add*` | Session loads its own config | `@hosting.configure(...)`, `@hosting_argparse.command(...)` |
| `builder.Services` (DI) | `AppSession` fields | Services record `S` from `@hosting.build(factory)` |
| `IHost` | `App` plus session | `Host[S]` |
| `IHostedService`, `IHostedLifecycleService` | `startup`, `shutdown` phases | `@hosting.service(name, starting~, start~, ...)` |
| (none) | `initialize`, `analyze` phases | `starting`, `started` hooks |
| `BackgroundService.ExecuteAsync` | `execute` phase | The command |
| `ApplicationStarted`, `ApplicationStopping`, `ApplicationStopped` | (none) | `on_started`, `on_stopping`, `on_stopped` |
| `StopApplication()` | (none) | `Lifetime::stop_application(exit_code?)` |
| `stoppingToken` | (none) | `ctx.cancelled()`, `StopToken` and task cancellation |
| `ConsoleLifetime` | (none); Morphir calls `exit(130)` | `@hosting_console.run` |
| `HostOptions.ShutdownTimeout` (30 s) | (none) | `@hosting.shutdown_timeout(ms)` (30 s) |
| `IHostEnvironment` | (none) | `HostEnvironment` |
| Host configuration (`DOTNET_` variables, args) | (none) | argparse first, then `<PREFIX>_ENVIRONMENT` |
| `Environment.ExitCode` | Last `Some(code)` wins; error gives 1 | `set_exit_code`; precedence in D8 |
| Shutdown after a failed start | `shutdown` runs with the error | Stop phase for started services |
| Panic skips shutdown | Panic skips shutdown | Panic is not caught. It is not a goal. |

## Risks / Trade-offs

- [The Zig stub may not build or link on one platform] → Task group 1 is a spike on
  Linux, macOS and Windows. Owner fallback: write the stub in C as a `native-stub`.
- [Consumers of the published module must not need Zig] → Owner: the package ships
  prebuilt stub objects for each native platform. If that is too complex to ship or
  link, the C fallback applies, and the consumer's C compiler builds the stub.
- [A signal handler must do only async-signal-safe work] → The handler stores two
  atomic values and, on a second signal, calls `_exit` or `ExitProcess`. Nothing else.
- [The watcher task wakes every 50 ms] → Small cost, and only in the console driver.
  Synchronous checks read the flag directly, so they do not wait for the watcher.
- [The `moonbitlang/async` runtime and the stub can both own a signal] → The driver
  turns off the runtime signal set. The spike verifies this on each platform.
- [Windows ends the process after a console close in about 5 seconds] → Document it.
  The stop phase after `CTRL_CLOSE_EVENT` cannot take more time.
- [`%async.run` is a compiler intrinsic, not a public API. wasm hosting relies on
  it] → Keep it in one file per target. If it goes away, wasm targets need
  `moonbitlang/async` support for wasm-gc or synchronous hooks.
- [js code that does not yield cannot see a signal] → Document the `@async.pause()`
  rule for js. Morphir keeps its worker thread on js.
- [Type inference for `HostBuilder[S]` across a long pipeline can fail] → Test the
  example as a compiled doc test. If it fails, annotate `let b : HostBuilder[App]`.
- [Signal handlers are global state] → Only the console driver installs them. Only
  one console host runs per process.
- [A cancelled command can leave partial output] → `defer` and `protect_from_cancel`
  are the tools. The stop hooks see the same state (D1).
- [An argparse option with an environment source reads the process environment
  inside argparse, not the variable set of the run] → The standard flags have no
  environment source. Document that an application option with one breaks the
  "no process read" rule for explicit runs.
- [`moonbitlang/async` is experimental] → Pin an exact version (0.22.5 was read for
  this design). Keep all use in drivers. The engine does not import it.

## Migration Plan

1. Run the Zig stub spike first. Implement the host after the three configuration
   changes.
2. morphir-moonbit moves in steps: first `@hosting.run` with exit codes and the
   telemetry `stopping` hook; then the console driver; then remove
   `interruption_start`, `interruption_stop`, the SIGINT part of `platform.c`, and the
   `"Cancelled"` compare. Its evaluator polls `StopToken::cancelled()` in place of
   `interruption_requested()`. `--cancel-file` can become an embedder probe.
3. Rollback: an application that does not use `@hosting` keeps its own `main`.
   Nothing else in Moon-Lander depends on the host.

## Open Questions

- Can the stub wake the event loop through a pipe in place of the 50 ms watcher? The
  spike can measure it. The watcher stays until then.
