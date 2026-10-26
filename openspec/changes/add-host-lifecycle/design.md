# Design: Add the host lifecycle

Labels: "Owner" marks a decision of the project owner. "Call" marks a designer
decision that the owner did not reject. "Call (this change)" marks a decision that
this change adds. The owner can change a Call without a change to the Owner decisions.
Items O1 to O3 and R1 to R12 come from the reconciliation addendum of 2026-10-20.
They replace earlier text where the two disagree. "Owner (2026-10-20)" marks the
later owner decisions on host starting settings (D13), the `IntoEnvVars` input (D14),
the local override layer of `configuration-conventions`, and the batteries-included
`@lander` entry (D15).

## Context

See proposal.md (Why). This section gives only the facts that shape the design.

- Moon-Lander has no host today. `pkgs/lander` exports only `version()`.
- Owner (2026-10-20): "lean on minimal config and sane defaults". The root package
  `@lander` is the batteries-included entry. `@hosting.builder` is the bare entry
  (D15).
- This change depends on `add-configuration-core` (`ConfigBuilder`, sources, the
  overrides source, `FileTree`, `LoadStep`, `@config.load`, `@host.load` (`moonrockz/moon-lander-config/host`),
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
native signal stub (O1, D7). Owner (2026-10-23): the stub is written in C. Zig was
only a means to this end.

### Platform limits that remain

1. **Signals on wasm and wasm-gc.** Not possible (Call). The lifetime stops through
   `stop_application` or an embedder probe.
2. **Shutdown timeout on wasm and wasm-gc.** Not possible without timers. Hooks on
   these targets must not suspend, so they cannot wait.
3. **Synchronous code that does not yield on js.** A Node.js listener does not run
   while a synchronous computation holds the stack. `ctx.cancelled()` cannot see the
   signal, and a second signal has no effect, until the code yields. Morphir keeps its
   worker-thread model on js. The native C stub removes this limit on native (D7).
4. **Windows close event.** After `CTRL_CLOSE_EVENT`, Windows ends the process when
   the handler returns or when the system time limit ends (about 5 seconds). The stop
   phase after a console close must end inside that limit. The host cannot extend it.
5. **Feasibility of the signal stub is not verified (O1).** Task group 1 is a spike.
   Owner (2026-10-23): the stub is a C `native-stub`, which the consumer's C compiler
   builds, as `moonbitlang/async` builds its own `signal.c`. An earlier plan wrote the
   stub in Zig and shipped prebuilt objects for each platform. It was dropped: the
   `link` settings in `moon.pkg` are keyed by backend (`native`), not by operating
   system or CPU, so a package cannot choose the prebuilt object for the consumer's
   platform without a build step that runs in every consumer.

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
- No shutdown timeout key that the framework owns. An application can opt in to a
  key that it names (D6).
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

This example is the bare path (D15). Morphir uses `@hosting.builder`, so it turns on
each part itself and reproduces Morphir exactly. The batteries path is in D15.

```moonbit
async fn main {
  "morphir"
  |> @lander_core.AppName::parse
  |> @hosting.builder(@env.args())
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
    |> @config.format(@toml.format())   // the bare builder registers no format
    |> @config.defaults(Defaults::default())
  })
  |> @hosting.app_dirs()   // = @conventions.add(@conventions.app_dirs(name, prefix~)) with host values
  |> @hosting.reserve_env(["MORPHIR_LOG_DIR"])
  |> @hosting.service("telemetry", stopping=fn(ctx) { ctx.services.logs.flush() })
  |> @hosting.shutdown_timeout(TimeLimit::seconds(5))
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
    ctx.lifetime.set_exit_code(@hosting.ExitCode::from_int(2))
  }
}
```

- Call (R8): the application name occurs one time, in `@lander.cli(name, args)` or
  `@hosting.builder(name, args)`. `@lander.cli` calls `@hosting.builder` and then
  turns on the defaults of D15. The argparse command gets the name through the
  `fn(name)` argument.
- Call (R8): the variable prefix defaults to the application name in upper case, with
  `-` changed to `_`. `|> @hosting.env_prefix("...")` changes it.
- Call (R8): the host composes the environment-variable source itself (D12). The
  application does not add `@config.env`.
- Call (R1, R8): `@conventions.app_dirs(name, prefix?, display?)` keeps a required name,
  so it works without a host. On the bare builder, `|> @hosting.app_dirs()` adds
  `@conventions.add(@conventions.app_dirs(name, prefix~))` with the name from
  `@hosting.builder` and the host prefix. Under `@lander`, this set is on by default
  (D15). The application gives the name one time.
- Call (this change): `@hosting.configure(fn(sources) { ... })` takes the
  `ConfigBuilder` pipeline of `configuration-core`. If core gives a builder trait,
  `HostBuilder[S]` implements it, and the direct form `|> @config.defaults(...)` also
  works.
- Call (2026-10-25): `@hosting.conventions(f)` transforms the host-owned
  conventions set. It starts from an empty `base` set; `app_dirs()` replaces it
  with the standard set using the final host name and prefix. Steps compose in
  pipeline order. The host adds the final set with the run's `DiscoveryOptions`
  and resolved environment name. A bare builder with neither step adds no reports.
- Call (R1): on wasm and wasm-gc, the application gives the file snapshot with
  `|> @hosting.files(tree)`. On native and js, the host reads files itself.
- Owner (2026-10-20): the variable set and the working directory of the run are
  host starting settings (D13). The application gives them to `@lander.cli` or
  `@hosting.builder`, or with later steps. Each omitted value comes from the process on native and js.

### D3. Run order (Owner: .NET model; Call (R7): argparse runs before any file read)

1. The host fixes the variable set and the working directory of the run (D13). It
   uses the conversion result stored at the builder step (D14), and fills each omitted value from the
   process on native and js. A conversion error ends the run with `UsageError` and
   exit code 2, before any file read. The host gives both values to the core builder
   (`@config.env_vars`, `@config.working_dir`).
2. The host parses `args` one time with core argparse `Command::try_parse` (D6,
   D11). An argparse error or a misused standard flag ends the run with
   `UsageError` and exit code 2, before any file read. A help or version request
   ends the run with code 0 and the reason `Requested`, before any file read, and
   the run returns: on native and js the console driver then ends the process with
   code 0, and on wasm and wasm-gc control returns to the embedder (D6, "Help and
   version in the embedded driver"). Settings come first
   because the parse reads the variable set of the run.
3. The host finds the environment name for `HostEnvironment`: the `--environment`
   value, then `<PREFIX>_ENVIRONMENT` in the variable set of the run, then the builder
   default. This is the same order that conventions uses, so both give the same name.
   It checks the name with the name rules of `configuration-conventions`. A bad name
   raises `ConfigError::InvalidEnvironmentName` (exit code 2).
4. The host makes `DiscoveryOptions` (`environment`, `config`, `isolated`, `project`)
   from the standard flags (D10), and gives it to the conventions parts.
5. The host loads the configuration. Native and js: `@host.load(builder)`.
   wasm and wasm-gc: `@config.load(builder, tree)` with the tree from
   `@hosting.files`. The merge order is the configure-callback sources in order,
   then the host-owned conventions set (System 100 through UserOverride 400),
   then the `<PREFIX>_*` source at 600, then the argparse overrides at 700
   (group 14). Core load requires priorities that do not go down. With
   `app_dirs()` or `conventions(f)`, configure sources must have priority 100 or
   less, such as defaults or an in-memory value at 0. A file at a higher priority
   belongs in the conventions set, or the application leaves out the host-owned set.
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
priv struct HostedService[S] {   // only `service` makes one (D17)
  name : ServiceName
  starting : Hook[S]?
  start : Hook[S]?
  started : Hook[S]?
  stopping : Hook[S]?
  stop : Hook[S]?
  stopped : Hook[S]?
}
pub type Hook[S] = async (Context[S]) -> Unit raise

pub fn[S] service(
  self : HostBuilder[S], name : &IntoServiceName,
  starting? : Hook[S], start? : Hook[S], started? : Hook[S],
  stopping? : Hook[S], stop? : Hook[S], stopped? : Hook[S],
) -> HostBuilder[S] raise HostError
```

- Owner: start in registration order, stop in reverse. .NET 8 order: all `starting`,
  then all `start`, then all `started`. Stop: all `stopping`, all `stop`, all
  `stopped`, each in reverse.
- Owner (2026-10-24): A service counts as started when its `start` hook returns without
  an error, or when the service has no `start` hook, the start phase reached its
  `starting` step, and its `starting` hook succeeded or is absent. A service that the
  start phase did not reach is not started. Only started services get stop hooks.
- Call (this change): a stop hook failure does not skip the next hooks. The host
  collects all failures.
- Stop hooks read the reason with `ctx.lifetime.stop_reason()`.
- Owner (2026-10-23, D17): each service of a host has its own `ServiceName`,
  without regard to letter case. A second service whose name equals a name of the
  builder, or differs from it only in letter case, raises
  `HostError::DuplicateService(name~, existing~)`, so a builder never holds two
  services that give one file.

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
- Call (this change): when the command, the services factory or a hook raises `StopRequested`, the host
  treats it as a normal stop, not as a failure. The stop reason stays the reason of the first
  request. A service whose `starting` or `start` hook raises `StopRequested` does
  not count as started.
- Call (this change): event handlers are synchronous and cannot raise. A handler
  that is registered after its event runs at once (like .NET token registration).
- Owner (2026-10-24): the first event that ends the run sets the stop reason once:
  a start failure gives `StartFailed`, a command failure gives `Failed`, command
  completion gives `Completed`, or the first stop request gives its request reason.
  A request after the reason is set records that a request occurred and keeps the
  first requested code, without changing the reason. All stop hooks read the same
  reason. Later requests have no effect, except that a signal still sets the signal
  exit code.
- Call (this change): a configuration or factory failure before the start phase sets
  the reason to `StartFailed(error)`.
- Call (this change): on native and js, a stop request also cancels the command task.
  The command stops at its next suspension point and its `defer` blocks run. A command
  protects a critical part with `@async.protect_from_cancel`.
- Call (this change): a stop request during the start phase lets the current hook
  end, skips the other start hooks and the command, and stops the started services.

### D6. Pure phase engine and drivers (Call: pure engine; Owner (2026-10-24): private engine with reply tokens, no type-state; Call (this change): drivers)

The engine is a state machine over explicit replies. It has no I/O and no async
code. It is private to `@hosting`: the drivers of the package (`run` and
`run_embedded`) use it, and white-box tests step through it on all four targets.
The console driver uses `@hosting.run`, so no other package needs the engine.

```moonbit
priv struct Engine { ... }        // phase, place, started services, failures, reason, code
priv enum Step {
  Run(Pending, Action)            // the driver runs the action, then replies with the token
  Finish(RunOutcome)              // no token, so the loop ends here
}
priv enum Action {
  Hook(ServiceRef, Phase)         // Phase: Starting, Start, Started, Stopping, Stop, Stopped
  RunCommand
  Raise(Event)                    // Event: Started, Stopping, Stopped
}
priv struct ServiceRef { ... }    // only the engine makes one, so it is always in range
priv struct Pending { ... }       // the reply token of one step
priv enum StopRequest { Requested } // group 4 adds Signal; group 13 adds Embedder

fn[S] Engine::start(services : Array[HostedService[S]]) -> Step
fn Pending::done(self : Pending) -> Step
fn Pending::failed(self : Pending, error : Error) -> Step
fn Pending::stop_requested(self : Pending, request : StopRequest, code : ExitCode?, result~ : ActionResult = Returned, observed_signal? : SignalKind) -> Step
fn Pending::timed_out(self : Pending, limit~ : @lander_core.TimeLimit, observed_signal? : SignalKind, result~ : ActionResult = Interrupted) -> Step
```

A driver is one loop:

```moonbit
let mut step = Engine::start(host.services)
while step is Run(pending, action) {
  step = try run_action(action) catch { e => pending.failed(e) } noraise { _ => pending.done() }
}
guard step is Finish(outcome)
```

- Owner (2026-10-24): no type-state (a type parameter for each phase). The next phase
  depends on runtime results, the service count is a runtime value, and the drivers
  share one loop. A private phase enum holds the state, and states that cannot occur
  stay inside the engine.
- Call (this change): each step that waits for a result carries a `Pending` token, and
  only that token advances the engine. So a driver cannot reply to a step that waits
  for nothing, or reply after `Finish`. MoonBit has no linear types, so a second reply
  to one token is possible; it gives the same step again and changes nothing.
- Call (this change): the engine reads which hooks each service has from the services.
  It skips an absent hook without a step. There is no separate count or hook mask.
- Call (this change): the engine implements all four replies. `stop_requested` follows
  D5: during the start phase, the current hook ends, the other start hooks and the
  command are skipped, and the started services stop. During the command, the stop
  phase starts. The first request records the request and its code. It sets the
  reason only if no reason is set, so all stop hooks read the same reason. Later
  requests change nothing; group 4 adds the signal
  exception in D5. The engine maps `StopRequest` to `StopReason`. `timed_out`
  outside the stop phase is a driver fault: the engine aborts and names the phase.
  In the stop phase: the other stop hooks are skipped, the stopped event occurs,
  and the code is 1. Group 4 connects the stop sources and group 10 the timeout.
  The timeout adds `ShutdownTimedOut(limit)` to the failures, after a failure of the current hook, and is reported for every exit code.
- Call (this change): the started event is the last step of the start phase. A stop
  request in reply to `Raise(Started)` skips the command. A `failed` reply on any
  `Raise` step is a driver fault: the engine aborts, because event handlers cannot raise.
- Call (this change): until group 4 adds `Lifetime`, a driver replies `done` to a
  `Raise` action at once. The engine collects each hook failure in the outcome. Group
  5 adds the report on standard error and the exit-code precedence.

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
- Call (group 13): the embedded driver is
  `pub fn[S] run_embedded(host : Host[S], command : Hook[S], stop_probe? : () -> Bool) -> RunOutcome`,
  synchronous, in `run.embedded.mbt` (wasm, wasm-gc). It uses the shared
  `configuration_inputs`, `configuration_from_tree`, `finish_configuration` and
  `outcome`, and the same reply rule after each step as `run` (one shared
  `Lifetime::reply`). Each hook, the command and a custom report run through
  `%async.run` inside `%async.capture_cancellation`. A probe of the pinned compiler
  on both targets showed that `%async.run` returns at the first suspension, and that
  a stored continuation can resume later outside it. So each step has its own open
  flag and result cell, which the driver closes when `%async.run` returns: a late
  resume cannot change a completed step or run.
- Call (group 13): a hook or command that suspends fails with
  `SuspendError::HookSuspended(service~, phase~)` or `CommandSuspended` (code 1), and
  the engine failure and stop rules apply. The message names the hook and says that
  hooks on wasm and wasm-gc must not wait. The public enum `HookPhase` names the
  phase, because the engine `Phase` stays private. A cancellation that the closure
  does not catch is a stop request, as in `run`.
- Call (group 13): the embedder probe is a stop probe that maps `true` to the private
  request `Embedder` and the reason `StopReason::Embedder`. The driver registers it
  before the first hook. A probe stop before the first hook runs no hook.
- Call (group 13): the default report writes `<name>: <message>` with core
  `eprintln`, so the driver links no event loop. On wasm that is WASI standard
  error. On wasm-gc, core has no standard-error channel, and `eprintln` writes to the
  one output import of core. A wasm-gc embedder that needs a separate channel gives
  `error_report`. A custom report that raises or suspends is ignored.
- Owner (2026-10-25), Call (group 13): **Help and version in the embedded driver.**
  `--help` and `--version` (and every other argparse help or version request, such as
  `help <subcommand>` or `arg_required_else_help`) return control to the embedder.
  The contract:
  - Output: the driver writes the text that argparse renders, one time, to standard
    output with `println`, the same text as on native and js.
  - Result: `run_embedded` returns a `RunOutcome` with exit code 0, no failures and
    the stop reason `Requested`, the same reason as a services factory that raises
    `StopRequested`, which also ends the run before any hook.
  - Order: the request ends the run after the argument parse and before the
    configuration load. No file of the tree is read, and the services factory, the
    lifetime and the hooks do not run.
  - No exit: the driver calls no process exit, and the built wasm and wasm-gc modules
    have no exit import (`proc_exit`, `__moonbit_sys_unstable.exit`). Today
    `Command::parse` links that import into every host, also when no argument asks for
    help.
  - Call (review of group 13): `run` on native and js uses the same entry point, so
    the host has one parse path. `run` writes the text and returns the same outcome,
    and `run` still does not end the process. The console driver then ends the
    process with code 0 (native) or sets `process.exitCode` (js), which keeps help
    text that is still in a pipe.
  - Parser: the driver uses one argparse parse of the same command. It does not read
    argv itself and does not add a second parser. The pinned public
    `Command::parse` catches the private help and version requests and exits, so the
    driver needs a public entry point that returns them. Upstream request:
    moonbitlang/core#4486, with `Command::try_parse(...) -> ParseOutcome` in
    moonbitlang/core#4487.
  - Owner (2026-10-26): until a pinned MoonBit release has `try_parse`, the host
    uses a vendored copy of core argparse with the patch of moonbitlang/core#4487
    (D11). The host does not wait for the release, and it does not weaken the
    contract: help and version stay built-in argparse features that need no step
    of the application, and no exit import is linked. A private `DisplayRequested(text)` carries the request from
    the parse to each driver, as `StopRequested` does from the factory.
    `mise run check:embedded` runs a wasm and a wasm-gc embedder with `--help` and
    `--version` and fails on an exit import in the built modules. Bead
    `lander-4us.5.18` returns to core.
- Call (this change): the shutdown timeout is one budget for the full stop phase. It
  starts when the command task has ended. Default 30 000 ms, as in .NET.
- Owner (2026-10-24): the builder sets the shutdown timeout with
  `@hosting.shutdown_timeout(limit : TimeLimit)`. An application can also opt in to
  a configuration key that it names, with
  `@hosting.shutdown_timeout_key(key : @config.KeyPath)`, so an operator can change
  the timeout without a rebuild (a file, a `<PREFIX>_*` variable or a mapped flag).
  The framework reserves no key. A value at the key overrides the builder value;
  with no value at the key, the builder value applies, and with neither, 30 s. The
  host reads the key one time, after the configuration load and before the
  services factory, through the `FromConfig` implementation of `TimeLimit` (text
  such as `10s` or `2m30s`). A value that does not parse is a `ConfigError`: code 2,
  and no hook runs. Group 9 adds the key step, because it needs the configuration
  load.

### D7. Console driver (Owner: SIGINT, SIGTERM, SIGQUIT give a graceful stop; Owner: O1, O2, O3)

The console driver is in `hosting/console`. It has one native part and one js part.

**Native: a C signal stub (Owner, O1; Owner (2026-10-23): C).** The stub is one C
source in `hosting/console`, listed in `native-stub` in `moon.pkg`, so the consumer's C
compiler builds it with the package. It uses `#ifdef _WIN32` for the Windows part, the
same pattern as `signal.c` in `moonbitlang/async`. MoonBit calls it through
`extern "c"`. `moonbitlang/async` stays for all other async work.

- Linux and macOS: the stub installs `sigaction` handlers for SIGINT, SIGTERM and
  SIGQUIT. SIGHUP keeps its default action, as in .NET `ConsoleLifetime` (Call).
- Windows: the stub calls `SetConsoleCtrlHandler` for `CTRL_C_EVENT`,
  `CTRL_BREAK_EVENT` and `CTRL_CLOSE_EVENT`.
- Mapping (Call, O3): SIGINT and `CTRL_C_EVENT` give `Interrupt`; SIGTERM and
  `CTRL_CLOSE_EVENT` give `Terminate`; SIGQUIT and `CTRL_BREAK_EVENT` give `Quit`.
- First signal: the handler stores the signal identity and sets an atomic stop flag.
  It does only async-signal-safe work.
- Second signal: the handler ends the process at once from inside the handler, with
  the exit code of the second signal (`_exit` on Linux and macOS, `TerminateProcess` on
  Windows). This works while the command runs synchronous code that never yields.
- `ctx.cancelled()` reads the atomic flag through one extern call (D5). Synchronous
  code sees the first signal at its next check.
- Call (this change): a watcher task polls the flag every 50 ms with `@async.sleep`.
  When the flag is set, it makes a stop request with `Signal(kind)`. That cancels
  the command task at its next suspension point.
- Call (group 11): the engine and the lifetime stay private, so the console package
  gives `@hosting.run` a small typed bridge, not a probe or a stop request:

  ```moonbit
  pub struct SignalProbe { priv request : () -> StopRequest? }
  pub fn SignalProbe::new(read : () -> SignalKind?) -> SignalProbe
  pub async fn[S] run(host : Host[S], command : Hook[S], signals? : SignalProbe) -> RunOutcome
  ```

  With `signals`, `run` registers the probe as a stop probe after the services
  factory and before the first hook, so each cancellation check reads the flag
  through one extern call. It runs the 50 ms watcher as a `no_wait` task of a task
  group around the start phase, the command and the stop phase. The group cancels
  the watcher when the run ends, so no task keeps the process open. The watcher and
  the checks share the one stop-request path of the lifetime (D5), so the first
  signal sets the reason and a later signal still sets the signal exit code.
- Call (group 11): the console package uses the one `@hosting.SignalKind`. The spike
  type `@console.SignalKind` is removed. A signal code (1 Interrupt, 2 Terminate,
  3 Quit) crosses only the C stub and Node.js adapter boundary, and one private
  function of the console package changes it into a `SignalKind`.
- Call (group 11): `@hosting_console.run(host, command)` is `async`. When the
  handlers cannot be installed, it raises `ConsoleError::SignalHandlersUnavailable`
  before it reads configuration or runs a hook. On js, the same error means that the
  runtime has no Node.js `process`.
- Call (this change): the driver makes sure that the `moonbitlang/async` runtime does
  not also handle these signals, through the public
  `@signal.set_global_cancellation_signals([])` of `moonbitlang/async/signal`. The
  spike verifies on each platform that this removes the runtime handlers.
- Call (this change): on `CTRL_CLOSE_EVENT` the handler waits until the process ends,
  so Windows does not end the process before the stop phase. The system time limit
  still applies (Platform limits, item 4).
- After the stop phase, the driver ends the process explicitly with the exit code
  (D8) through libc `exit`, which flushes standard output.
- Call (group 11): the C stub exports its pure event and signal mappings
  (`moonlander_console_kind_of_event`, `moonlander_console_kind_of_signal`,
  `moonlander_console_exit_code`), and the handlers call them. A native unit test
  calls the same functions, so the mapping of `CTRL_C_EVENT` and `CTRL_CLOSE_EVENT`,
  which a CI runner cannot send to one child, has a test on every platform.

**js: the TypeScript adapter (Owner, O2).** The js console lifetime lives in a
TypeScript adapter. Owner (2026-10-23, `split-framework-modules` D2): it is the
hosting node adapter `pkgs/hosting/adapters/node`, not the `config/host` adapter,
so the configuration module has no process-signal code. It has the same rules: it
uses only `node:*` APIs, and `build-node-adapter.mbtx` bundles it with Bun as a
second entry point. MoonBit js externs call it.

- The adapter installs `process.on` listeners. Linux and macOS: SIGINT, SIGTERM,
  SIGQUIT. Windows: SIGINT (Ctrl-C), SIGBREAK (Ctrl-Break) and SIGHUP (console close),
  which Node.js gives for the Windows console events. Call (this change): the mapping
  is the same as native: SIGBREAK gives `Quit`, SIGHUP on Windows gives `Terminate`.
- The first signal calls `stop_application` with `Signal(kind)`.
- A second signal calls `process.exit(code)` at once with the code of that signal.
- At the end, the driver removes the listeners and sets `process.exitCode` to the
  exit code. It does not call `process.exit` on a graceful stop, because that can drop
  output that is still in a pipe.
- Call (review of groups 11 and 12): after a graceful signal stop on js, the driver
  sets `process.exitCode` and starts a 2 s timer that does not keep the event loop
  open (`unref`) and then calls `process.exit(code)`. A process with no other work
  ends first and keeps its piped output. A timer or socket that a service left
  open cannot keep the process running after a signal, so the host ends the process
  explicitly, as the spec "Exit codes" requires. A clean end only sets
  `process.exitCode`.
- Call (review of groups 11 and 12): a signal that arrives during configuration
  loading or the services factory runs no start hook: the run replies to the first
  engine step with the stop request without running it. When a failure before the
  engine ends the run, a recorded signal still selects the signal exit code. A
  signal that arrives after the last probe read of the run also selects the signal
  code in both drivers.
- Call (group 12): the listeners are the entry point `signals.ts` of the hosting
  node adapter. `build-node-adapter.mbtx` bundles it into the console package
  (`pkgs/hosting/console/node.generated.js.mbt`), because the generated factory of
  `index.ts` is private to `@hosting`. The js driver gives `@hosting.run` the same
  `SignalProbe` as native, so the listener only records the first kind and the
  watcher makes the stop request.
- Call (groups 11 and 12): `moonbitlang/async/process` has no js part, so a js
  program cannot start or signal a child. The native acceptance suite
  `tests/console-signal-acceptance` starts the test host as a native child and as a
  js child (`tests/console-host-program`) under Node.js and Bun. On Windows it sends
  a real `CTRL_BREAK_EVENT` to the process group of each child, which Node.js gives
  as SIGBREAK. `mise run check:console` builds the js program and runs the suite on
  Linux, macOS and Windows CI.
- Synchronous code that does not yield cannot see a signal on js (Platform limits,
  item 3).

### D8. Exit codes (Owner: 130, 143; Call: 1 and 2 match morphir-moonbit; Call (O3): 131 and explicit codes)

```moonbit
pub struct ExitCode { priv code : Int } derive(Eq, Debug)
pub fn ExitCode::from_int(code : Int) -> ExitCode raise HostError  // 0 to 255
pub fn ExitCode::success() -> ExitCode                         // 0
pub fn ExitCode::failure() -> ExitCode                         // 1
pub fn ExitCode::to_int(self : ExitCode) -> Int
```

Owner (2026-10-23, D17): an exit code is in the range 0 to 255, which every
platform keeps. `ExitCode::from_int` raises `HostError::InvalidExitCode` for any other
number, so no `ExitCode` value is out of range.

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

The D17 types replace the `String` fields and the `is_environment` parameter in this sketch.

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
- Call (R8): `|> @hosting.default_environment(@conventions.EnvironmentName::parse("Production"))` sets the default and
  also enables the environments part. Environment files need a primary part such
  as `app_dirs()`. `|> @conventions.environments()` enables the files
  without a default.
- Owner (2026-10-20): under `@lander`, environment-file discovery is on with no
  default name, so files load only when the run has a name. `|> @lander.no_environments()`
  turns it off. The bare `@hosting.builder` and the Morphir preset keep environment
  files off (D15).
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

- Call (R7): on the bare `@hosting.builder`, the standard flags are opt-in. The
  application adds each one to its argparse command. The host knows them by their
  ids.
- Owner (2026-10-20): under `@lander`, the standard flags are on.
  `|> @lander.no_standard_flags()` turns them off (D15).
- Call (this change): when the standard flags are on, the host adds the four flags
  to the root argparse command: the command from the `command` step, or the empty
  command named after the application. The host does not add a flag that the
  application already added with the same id.
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
- Owner (2026-10-26), Call (group 13): `hosting/argparse` re-exports the argparse
  types of a command with `pub using` (`Command`, `Matches`, `FlagArg`, `OptionArg`,
  `PositionArg`, `ArgGroup`, `FlagAction`, `OptionAction`, `ValueRange`,
  `ValueSource`). Applications build the command with these names, so the return
  from the vendored copy to core (D11) does not change application code.
  A command-definition fault also gives `UsageError` and code 2 because core argparse does not distinguish it from a user error without matching message text.

### D11. Package layout (Call: shared names)

The root package defines `command` because it needs the private builder fields; `hosting/argparse` re-exports it with `pub using`.

| Package | Targets | Contents |
| --- | --- | --- |
| `moonrockz/moon-lander-hosting` | all | Builder, `Host[S]`, `Context[S]`, engine, lifetime, environment, `ExitCode`, `UsageError`, `StopRequested`, `IntoEnvVars`, starting settings (`env_vars`, `working_dir`), env source composition, `run` (native, js), `run_embedded` (wasm, wasm-gc), `files` (wasm, wasm-gc) |
| `moonrockz/moon-lander-hosting/console` | native, js | C signal stub and native driver; js driver over the TypeScript adapter; process exit |
| `moonrockz/moon-lander-hosting/argparse` | all | `command`, standard flags, mappings, overrides source, argparse type re-exports (D10) |
| `moonrockz/moon-lander-hosting/vendor/argparse` | all | Temporary: a copy of `moonbitlang/core/argparse` with `Command::try_parse` (D6), and its private `vendor/internal/edit_distance` |
| `moonrockz/moon-lander` (`@lander`) | all | Batteries-included entry (D15): `cli` with the starting settings, the default steps (`formats`, `conventions`, `no_standard_flags`, `no_environments`, `build`, `run`) and `pub using` re-exports of `@hosting` steps |

- `hosting` imports `config`, `config/conventions`, `config/host` (native and js) and
  `moonbitlang/core/argparse` (for `Context[S].args`).
- Owner (2026-10-26), Call (group 13): until a pinned MoonBit release has
  `Command::try_parse`, `hosting`, `hosting/argparse` and the tests import
  `vendor/argparse` in place of `moonbitlang/core/argparse`, under the alias that they
  used for core. The copy is the core package of the pinned MoonBit release with the
  patch of moonbitlang/core#4487, byte for byte, except one import line: the core
  `internal/edit_distance` package moves to `vendor/internal/edit_distance`, because
  a package outside core cannot import a core `internal` package. The copy keeps its
  Apache-2.0 license, `NOTICE` and upstream tests. The return (bead
  `lander-4us.5.18`) changes the pin, the four `moon.pkg` imports, and deletes
  `pkgs/hosting/vendor`; no `.mbt` source line changes.
- `@lander` imports `hosting`, `hosting/argparse`, `hosting/console` (native and js),
  `config/conventions` and the virtual package `moonrockz/moon-lander-config/formats` of
  `add-configuration-core`. `hosting` does not import `formats`, so the bare path
  links no format that the application does not register.
- Call (O1): AGENTS.md gets a narrow exception: the native signal handlers in
  `hosting/console` use a C stub. All other process and filesystem work stays with
  `moonbitlang/async`. A task in this change makes that edit. The TypeScript exception
  belongs to the `config/host` js story (R12). `split-framework-modules` extends it to
  the hosting node adapter `pkgs/hosting/adapters/node`, which task 12.1 creates.

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
  - `Process`: no step. The set is the one from `@lander.cli` or `@hosting.builder`, which is the process
    variables on native and js when `env_vars` is omitted, and empty on wasm.
  - `Explicit(vars)`: `|> @hosting.env_vars(vars)` with `vars : &IntoEnvVars`. It
    replaces the set for every reader, not only for this source.
  - `Skip`: `|> @hosting.skip_env_source()`. The `<PREFIX>_*` source loads nothing and
    reports `skipped`. The set stays for the bootstrap and the directories.
- `@conventions.app_dirs` gets the application name and the prefix from the host, so
  `$<PREFIX>_HOME` and the variable source use one prefix.

### D13. Host starting settings (Owner (2026-10-20): like .NET `HostApplicationBuilderSettings`)

The starting setting `environment?` takes an `EnvironmentName` (D17).

```moonbit
// @lander: the batteries-included entry (D15)
pub fn cli(
  name : @lander_core.AppName,
  args : Array[String],
  env_vars? : &@hosting.IntoEnvVars,
  working_dir? : @lander_core.AbsolutePath,
  environment? : String,
) -> @hosting.HostBuilder[Unit]

// @hosting: the bare entry, with the same starting settings
pub fn[S] builder(
  name : @lander_core.AppName,
  args : Array[String],
  env_vars? : &IntoEnvVars,
  working_dir? : @lander_core.AbsolutePath,
  environment? : String,
) -> HostBuilder[S]

pub fn[S] env_vars(self : HostBuilder[S], vars : &IntoEnvVars) -> HostBuilder[S]
pub fn[S] env_prefix(self : HostBuilder[S], prefix : @lander_core.EnvPrefix) -> HostBuilder[S]
pub fn[S] working_dir(self : HostBuilder[S], path : @lander_core.AbsolutePath) -> HostBuilder[S]
```

- Owner: each run has one starting variable set and one working directory. Nothing
  reads the process environment or the process working directory, except where the
  host fills an omitted value.
- Owner: on native and js, an omitted `env_vars` or `working_dir` comes from the
  process through `moonbitlang/core/env`. Call: on wasm and wasm-gc, an omitted
  `env_vars` is the empty set and an omitted `working_dir` is `/`.
- Call (this change): the host fills omitted values one time, in run step 1 (D3), and
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
  `@immut/sorted_map.SortedMap[String, String]` from `moonbitlang/core`: the host
  makes it one time per run in deterministic key order and never changes it.
  Config and argparse get map copies at their boundaries.
- Call: on native and js, a missing process working directory ends the run with
  read-only `WorkingDirectoryError::MissingWorkingDirectory` and code 1 through
  the normal error report, before any file read or hook.
- Call (O3): the working directory uses `/` as the separator on every platform. The
  host converts a Windows process working directory at the boundary. Only drive
  and backslash UNC forms convert `\` to `/`. POSIX backslashes stay name characters.
  The path text keeps `.`, `..` and trailing separators; UNC roots need a server
  and a share.

### D14. Variable set from a map or JSON (Owner idea; Call on shape, verified with a `moonc v0.10.15` probe)

```moonbit
pub trait IntoEnvVars {
  into_env_vars(Self) -> Map[String, String] raise UsageError
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
let acme = "acme" |> @lander.AppName::parse
acme |> @lander.cli(["build"], env_vars={ "HOME": "/home/test" }, working_dir=@lander_core.AbsolutePath::parse("/w"))
acme |> @lander.cli([], env_vars=({ "ACME_PORT": 8080, "ACME_DEBUG": true } : Json))
acme |> @lander.cli([], env_vars=fixture)   // fixture : Json from @json.parse
acme |> @lander.cli([], env_vars=Map([]))
```

The builder and `env_vars` step snapshot the conversion result when applied,
including a conversion error. The run raises a stored error in step 1. Later
changes to the caller map or JSON object cannot change the host.

JSON rules (Call):

- The root must be an object. Any other root raises `UsageError` (exit code 2).
- A string value stays as it is.
- A Boolean or a number becomes its JSON text, for example `true` and `1`.
- An array or an object becomes its JSON text. The core environment source parses a
  value that starts with `[` or `{` as JSON, so the value comes back the same.
- `null` means that the variable is not set.
- A nested object is not flattened into `__` names.
- Keys stay exactly as written.

### D15. Batteries-included `@lander` entry (Owner (2026-10-20); Call (this change): API shape)

Owner: "lean on minimal config and sane defaults". There are two entry layers:

- `@lander.cli(name, args, env_vars?, working_dir?, environment?)` in the root package
  `moonrockz/moon-lander` (`pkgs/lander`) is batteries-included. It turns on the
  defaults below. Each default can be turned off or changed.
- `@hosting.builder(name, args, env_vars?, working_dir?, environment?)` is bare, like
  .NET `Host.CreateEmptyApplicationBuilder`. It turns on no default of the table. The
  Morphir preset builds on it, so it reproduces Morphir exactly (D2).

| Default | `@lander.cli` | Change or turn off | `@hosting.builder` |
| --- | --- | --- | --- |
| Formats | The set from the `formats` virtual package of `add-configuration-core` (default: TOML, YAML, JSON through JSON5, JSON5, Ion) | `\|> @lander.formats(["toml", "yaml"])` | None. The application registers formats. |
| Conventions | `app_dirs(name, prefix~)`: system, XDG, application home, three layouts, local and user overrides, walk-up | `\|> @lander.conventions(fn(c) { ... })` | None. `\|> @hosting.app_dirs()` adds them. |
| Standard flags | `--config`, `--environment`, `--isolated`, `--project` on | `\|> @lander.no_standard_flags()` | Opt-in (D10) |
| Environment files | Discovery on. Files load only when the run has an environment name. | `\|> @lander.no_environments()` | Off |
| Variables source | `<PREFIX>_*` at 600; `<PREFIX>_HOME` and `<PREFIX>_ENVIRONMENT` reserved | `\|> @lander.env_prefix(...)`, `\|> @lander.skip_env_source()` | Same (D12) |
| Services | `S = Unit` when the application does not call `build` | `\|> @lander.build(factory)` | `\|> @hosting.build(factory)` gives `Host[S]` |
| Driver | Console driver on native and js, embedded driver on wasm and wasm-gc | `\|> @lander.run(command)` | The application selects a driver |
| Shutdown timeout | 30 s, as in .NET | `\|> @lander.shutdown_timeout(limit)` | Same (D6) |

The smallest program:

```moonbit
fn main raise {
  "acme"
  |> @lander.AppName::parse
  |> @lander.cli(@env.args())
  |> @lander.run(fn(ctx) { ... })
}
```

A larger program in the one batteries style. It uses only `@lander` steps:

```moonbit
fn main raise {
  "acme"
  |> @lander.AppName::parse
  |> @lander.cli(@env.args())
  |> @lander.configure(fn(sources) { sources |> @config.defaults(Defaults::default()) })
  |> @lander.build(fn(b) { App::new(b.config) })
  |> @lander.service("telemetry", stopping=fn(ctx) { ctx.services.logs.flush() })
  |> @lander.shutdown_timeout(TimeLimit::seconds(5))
  |> @lander.run(fn(ctx) { acme_command(ctx) })
}
```

- Owner: the defaults in the table. This supersedes, for the `@lander` entry only, the
  earlier calls "standard flags are opt-in" (D10, R7) and "environments are opt-in"
  (D9, conventions D10). The bare builder and the Morphir preset keep both off.
- Call (this change): a `@lander` step that has the same behavior as a `@hosting`
  step is an alias: a `pub using` re-export, so one function has one document. The
  re-exports are `service`, `configure`, `env_prefix`, `reserve_env`,
  `skip_env_source`, `env_vars`, `working_dir`, `default_environment`, `files`,
  `error_report` and `shutdown_timeout` from `@hosting`, the types `AppName`,
  `AppNameError` and `AppNameRule` from `moonrockz/moon-lander-core`,
  `EnvironmentName` from `moonrockz/moon-lander-config/conventions`, the types
  `ServiceName`, `IntoServiceName`, `ExitCode` and `HostError` from `@hosting` (D17), and `command` and
  `map` from `hosting/argparse`. A step with batteries behavior is a thin wrapper: `cli`,
  `formats`, `conventions`, `no_standard_flags`, `no_environments`, `build` and `run`.
  So a batteries application writes only `@lander` steps. Probe (`moonc v0.10.15`,
  scratchpad, 2026-10-20): `pub using @hosting {shutdown_timeout}` re-exported a
  generic top-level function on wasm, wasm-gc, js and native, and `moon info` listed
  it in the `@lander` interface. `fnalias` no longer parses.
- Call (this change): `@lander.cli` gives `HostBuilder[Unit]`. `@lander.build(factory)`
  gives `HostBuilder[S]` and keeps every earlier setting. A hosted service that the
  application registered before `build` keeps its place in the order and gets a
  context whose `services` value is `()`. The same probe showed that a step that
  changes the type parameter compiles on all four targets. `@hosting.build` keeps its
  shape: it gives `Host[S]` for the bare path.
- Call (this change): `@lander.formats(names)` keeps the linked formats whose `name`
  is in `names`, in linked order. These formats are the builder registry, so
  discovery searches and explicit files parse only them. A name that the linked set
  does not hold is a fault in the program: the run ends before any file read with
  exit code 1, and the report names the unknown name and the linked names.
- Call (this change): `@lander.conventions(f)` takes
  `(@conventions.Conventions) -> @conventions.Conventions` and is a thin wrapper
  over `@hosting.conventions(f)`. `f` gets the default set
  `app_dirs(name, prefix~)`, so the name stays in `@lander.cli`. For example,
  `fn(c) { c |> @conventions.without(...) }` removes one part, and
  `fn(_) { @conventions.base("acme") |> ... }` replaces the set.
- Call (this change): `@lander.run(command)` uses one file per target group. On native
  and js it builds the host and runs `@hosting_console.run`. On wasm and wasm-gc it runs
  `@hosting.run_embedded`. It is a synchronous function on all four targets, so one
  `fn main` source builds everywhere: wasm-gc has no `async fn main` (Platform
  findings). On native and js, it starts the `moonbitlang/async` event loop through
  the entry that `async fn main` uses (`run_async_main` in 0.22.5). That entry is
  hidden and marked "do not call directly" (see Risks). `@hosting.run` stays for
  tests. It returns a `RunOutcome` and does not end the process.
- Owner: the users of an application need no configuration file. Under `@lander`,
  a run with no file uses the defaults, and each discovered location reports
  `not-found`. An empty file is valid. A file at any position in the source list sets
  only the keys that it holds. Each option has a default, from the defaults source or
  from `bind_or` (`configuration-binding`).
- Call (this change): the owner's "origin `default`" is the core report kind name
  `defaults` (core D4). `@config.show` and `@config.explain` read only the `Config`.
  A `bind_or` default is not in the `Config`, so they cannot show it. An application
  that wants `config show` to list a default with its origin puts it in the defaults
  source with `@lander.configure`.

### D16. Program trait and `run_app` (Owner (2026-10-20): run takes a lambda or an object; Call: shape)

The owner asked that `@lander.run` take an object that implements a trait, as well
as a lambda. A probe with `moonc v0.10.15` on all four targets fixed the shape:

- MoonBit has no generic traits (`trait Command[S]` does not parse), no method type
  parameters (`run[S](...)` does not parse), no trait implementation for a function
  type (error 4053), and no function overloading. So one `run` cannot take both
  forms, and a command trait cannot be generic over `S`.
- `async` trait methods, `&Trait` objects and `fn[C : Trait]` bounds work.
- A context typed by the implementer works:
  `trait Program { async run(Self, Context[Self]) -> Unit raise }`.

Decision (Call): the services record is the program.

```moonbit
pub(open) trait Program {
  async run(Self, Context[Self]) -> Unit raise
}

struct App { logs : TelemetrySession }
impl @lander.Program for App with run(self, ctx) -> Unit raise {
  self.logs.info("start")
  build_all(ctx)                         // ctx.services is this App
}

// lambda form
"acme" |> @lander.AppName::parse |> @lander.cli(@env.args()) |> @lander.run(fn(ctx) { ... })

// object form
"morphir" |> @lander.AppName::parse |> @lander.cli(@env.args()) |> @lander.run_app(App::new)  // (BuildContext) -> App raise
```

- `run_app(factory)` is `build(factory)` followed by
  `run(fn(ctx) { ctx.services.run(ctx) })`. Both forms use one engine and the same
  driver selection.
- `@hosting` holds the trait and `run_app` for the bare builder. `@lander`
  re-exports both with `pub using`.
- An application with subcommands matches on `ctx.args` inside `run`, or keeps
  one handler object for each subcommand in `S`.
- Limit: a command object that is separate from `S` cannot be typed against
  `Context[S]`. Revisit if MoonBit adds generic traits.

### D17. Domain types (Owner (2026-10-23): no primitive obsession; parse, do not validate)

Owner: a value with rules is a type with private fields and one smart
constructor, so a value that breaks its rules cannot exist. `AGENTS.md` (Domain
types) holds the repository rule. The caller parses each value one time, where it
is written. After the parse, the host takes the type, not the raw value, and does
not check the rules again.

`EnvPrefix` and `AbsolutePath` live in `moonrockz/moon-lander-core` so config and hosting share their rules.

| Value | Type | Rule | Group |
| --- | --- | --- | --- |
| Application name | `AppName::parse(text)`, in `moonrockz/moon-lander-core` since `split-framework-modules` | Starts with an ASCII letter; then only ASCII letters, digits, `-` and `_` | 2 |
| Service name | `ServiceName::parse(text)` | Safe as one file path component: starts with a Unicode identifier start character (`XID_Start`, letters and letter numbers); then identifier characters (`XID_Continue`: letters, combining marks, digits, `_` and a few connectors), `-` and `.`; no invisible character; does not end with `.`; is not a Windows device name such as `CON` or `com1`; at most 128 bytes in UTF-8. Unique in one host without regard to letter case. | 2 |
| Exit code | `ExitCode::from_int(code)`, `ExitCode::success()`, `ExitCode::failure()` | 0 to 255 | 2 |
| Variable prefix | `EnvPrefix::parse(text)`; `AppName` gives the default prefix and cannot fail | Starts with an upper-case ASCII letter or `_`; then only upper-case ASCII letters, digits and `_` | 7 |
| Environment name | A parsed type in place of `String` (D3, D9, D13) | The name rules of `configuration-conventions` | 8 |
| Working directory and content root | `AbsolutePath` with `/` separators for Windows forms (D9, D13) | Not empty; absolute; a UNC root has a server and share; keep path text as written | 7, 8 |
| Shutdown timeout | `TimeLimit` from `moonrockz/moon-lander-core` (Owner, 2026-10-23; `split-framework-modules`) | 1 ms to the largest `Int` in milliseconds | 10 |

- Owner: the caller parses, so `@lander.cli` and `@hosting.builder` take an
  `AppName`, and `service` takes a `ServiceName`. The name is the first argument,
  so the text flows through the parse into the pipeline:
  `"acme" |> @lander.AppName::parse |> @lander.cli(@env.args())` (Owner,
  2026-10-24: the examples use this form).
- Owner (2026-10-24): `service` takes `name : &IntoServiceName`, like
  `IntoEnvVars` (D14): a `ServiceName`, or a `String` that the step parses with
  `ServiceName::parse`. MoonBit has no overloading, so a sealed trait with two
  implementations gives one step that takes both. The text is parsed at the step,
  which already raises `HostError`, and the host holds only the `ServiceName`
  after it. So `|> @hosting.service("db", start=...)` and
  `|> @hosting.service(ServiceName::parse("db"), start=...)` give the same
  service. `cli` and `builder` still take only an `AppName`, because they do not
  raise. A program parses its name in
  `fn main raise`, or in an `async fn main`. A bad name in a synchronous `main`
  stops the program at start with the error and a stack trace (probe, `moonc
  v0.10.17`: abort, exit code 134). In an `async fn main` the `moonbitlang/async`
  entry prints the error and gives exit code 1.
- Call (this change): one public `suberror HostError` holds the faults of a host
  set-up: `InvalidServiceName(text~, reason~)`,
  `DuplicateService(name~)` and `InvalidExitCode(code~)`. The change
  `split-framework-modules` moved `AppName` to core, so an invalid application
  name raises the core `AppNameError::InvalidAppName(text~, rule~)`, with the
  rule as an `AppNameRule` case. `HostError::message` gives
  text for people. A fault in the program is not a `ConfigError` or a
  `UsageError`, because no user input caused it.
- Call (this change): `AppName` allows no `.`, so `<app>.<env>.<ext>` stays
  unambiguous, and no path separator or whitespace, so it is safe in file and
  directory names. It starts with a letter, so the default prefix is a valid
  variable name.
- Owner (2026-10-23): a service name accepts every Unicode letter, and it must be
  safe as one component of a file path. The parse uses the Unicode identifier
  properties `XID_Start` and `XID_Continue` from `moonbit-community/unicode-data`
  (`xid` and `case_mapping` packages), because `moonbitlang/core` has no Unicode
  category data. These exclude every separator, reserved punctuation, whitespace,
  control and direction character. `XID_Continue` also allows a few connector
  characters such as `·` and `‿`, which are safe in a path. The parse rejects the
  invisible identifier characters (the default-ignorable code points in
  `XID_Continue`, such as U+200C, U+200D and the variation selectors, and the
  Hangul fillers): macOS HFS+ ignores U+200C and U+200D in names, and a report
  cannot show them. The rule also rejects a trailing `.` (Windows
  removes it), the Windows device names `CON`, `PRN`, `AUX`, `NUL`, `COM0` to
  `COM9` and `LPT0` to `LPT9` before any extension, and more than 128 UTF-8 bytes
  (a path component holds at most 255).
- Owner (2026-10-23): two service names that differ only in letter case are
  duplicates in one host, because Windows and macOS give them one file. The
  check compares the lowercase of the uppercase of each character, so pairs whose
  case mappings are not symmetric also match: `Σ`, `σ` and `ς`; `µ` and `μ`;
  `ſ` and `s`; `ß` and `SS`.
- Owner (2026-10-23): the parse does not normalize to NFC. A release-build probe
  measured the cost over the ASCII rule: the letter and case data add about 11 KB
  (wasm-gc), 29 KB (js) and 6 KB (native); NFC
  (`moonbit-community/unicode-normalization`) adds about 205 KB, 380 KB and 200 KB.
  The limit: two names that differ only in normalization form (`é` as one
  character, or `e` and a combining accent) are two services, and macOS gives them
  one file. Add NFC in `ServiceName::parse` if a real case needs it.
- Call (this change): a smart constructor that reads text is `parse`; one that
  takes a number is `from_<type>`, for example `ExitCode::from_int`.
- Call (this change): the signatures in D3, D6, D9, D12 and D13 that still show
  `String` or `Int` for a value in the table change in the group that the table
  names. The planned types follow this decision.

### Mapping from .NET and starbase

| .NET | starbase 0.13.3 | Moon-Lander |
| --- | --- | --- |
| `Host.CreateApplicationBuilder(args)` | `App::default()` | `@lander.cli(name, args)` (defaults on, D15) |
| `Host.CreateEmptyApplicationBuilder(settings)` | (none) | `@hosting.builder(name, args)` (no defaults, D15) |
| `HostApplicationBuilderSettings` | (none) | Optional labelled arguments of `@lander.cli` and `@hosting.builder` (`env_vars?`, `working_dir?`, `environment?`) |
| `builder.Configuration.Add*` | Session loads its own config | `@hosting.configure(...)`, `@hosting_argparse.command(...)` |
| `builder.Services` (DI) | `AppSession` fields | Services record `S` from `@hosting.build(factory)` |
| `IHost` | `App` plus session | `Host[S]` |
| `IHostedService`, `IHostedLifecycleService` | `startup`, `shutdown` phases | `@hosting.service(name, starting~, start~, ...)` |
| (none) | `initialize`, `analyze` phases | `starting`, `started` hooks |
| `BackgroundService.ExecuteAsync` | `execute` phase | The command |
| `ApplicationStarted`, `ApplicationStopping`, `ApplicationStopped` | (none) | `on_started`, `on_stopping`, `on_stopped` |
| `StopApplication()` | (none) | `Lifetime::stop_application(exit_code?)` |
| `stoppingToken` | (none) | `ctx.cancelled()`, `StopToken` and task cancellation |
| `ConsoleLifetime` | (none); Morphir calls `exit(130)` | `@hosting_console.run`, or `@lander.run` (D15) |
| `HostOptions.ShutdownTimeout` (30 s) | (none) | `@hosting.shutdown_timeout(limit)` (30 s) |
| `IHostEnvironment` | (none) | `HostEnvironment` |
| Host configuration (`DOTNET_` variables, args) | (none) | argparse first, then `<PREFIX>_ENVIRONMENT` |
| `Environment.ExitCode` | Last `Some(code)` wins; error gives 1 | `set_exit_code`; precedence in D8 |
| Shutdown after a failed start | `shutdown` runs with the error | Stop phase for started services |
| Panic skips shutdown | Panic skips shutdown | Panic is not caught. It is not a goal. |

## Risks / Trade-offs

- [The C stub may not behave the same on one platform] → Task group 1 is a spike on
  Linux, macOS and Windows, and in a consumer module outside the workspace.
- [Windows console events are hard to send from a test] → `GenerateConsoleCtrlEvent`
  needs a process group that shares a console, and `CTRL_CLOSE_EVENT` cannot be sent
  from a program. The spike finds what a CI runner allows and records any event that
  only a manual check covers.
- [A signal handler must do only async-signal-safe work] → The handler stores two
  atomic values and, on a second signal, calls `_exit` or `TerminateProcess`. Nothing else.
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
- [Solved: an argparse option with an environment source could read process
  variables] → The host supplies a map copy of the run snapshot to argparse.
- [`@lander.run` calls the hidden `moonbitlang/async` entry `run_async_main`, which
  its source marks "do not call directly"] → Keep the call in the native and js file
  of `@lander.run`. A task verifies it. Fallback: on native and js, `@lander.run` is
  `async`, and the program uses `async fn main` there and a per-target main file for
  wasm and wasm-gc. Tell the owner if the fallback applies.
- [The `formats` virtual package override is verified only inside a `moon.work`
  workspace, not from a consumer that gets `moonrockz/moon-lander` from mooncakes.io]
  → `add-configuration-core` owns the risk and a pre-publish check (core D15).
- [Defaults on by default can surprise an application that expects nothing] → Each
  default has one step that turns it off, and the bare `@hosting.builder` turns on
  nothing.
- [The vendored argparse copy misses upstream fixes and makes core argparse types
  not fit the `command` step] → The copy is temporary, unmodified and tested by its
  upstream tests on all four targets. Applications use the `@hosting_argparse`
  re-exports, so the return is a change of imports only. Bead `lander-4us.5.18`
  tracks the return.
- [`moonbitlang/async` is experimental] → Pin an exact version (0.22.5 was read for
  this design). Keep all use in drivers. The engine does not import it.

## Migration Plan

1. Run the C signal stub spike first. Implement the host after the three
   configuration changes.
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
- Revisit the wasm driver choice if `moonbitlang/async` gets a WASI 0.3 backend.
  Today its wasm event loop calls its own `"moonbitlang/async"` host imports, which
  only `moonrun` supplies, so no standard runtime (for example Wasmtime) can run
  `@hosting.run` on wasm. With a WASI 0.3 backend, wasm could use the async driver.
