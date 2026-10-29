# moonrockz/moon-lander-hosting

The host of a Moon-Lander application. A host builder holds the application
name, the arguments, the hosted services and a services factory. `build` gives a
`Host`, and `run` starts the services, runs the command and stops the services in
a known order, with a clear exit code. On wasm and wasm-gc, `run_embedded` does
the same without an event loop. Each run has a lifetime for events,
stop requests and cancellation checks. The run resolves its starting settings,
then parses arguments, loads configuration, builds services and runs hooks.
The console driver in [`moonrockz/moon-lander-hosting/console`](console/README.mbt.md)
changes console signals into a graceful stop and ends the process with the exit code.

Import the root package with an explicit alias, because the module name has `-`
in it. The application name comes from `moonrockz/moon-lander-core`:

```moonbit notest
///|
import {
  "moonrockz/moon-lander-core" @lander_core,
  "moonrockz/moon-lander-hosting" @hosting,
}
```

The module `moonrockz/moon-lander` gives the batteries-included entry
`@lander.cli`. This module gives the bare entry `@hosting.builder`:

```mbt check
///|
test "build a host with one service" {
  let log = []
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder(["greet"])
    |> @hosting.service(
      "greeter",
      start=_ => log.push("greeter started"),
      stop=_ => log.push("greeter stopped"),
    )
    |> @hosting.build(_ => ())
  ignore(host)
  // The build runs no hook.
  assert_eq(log, [])
}
```

| Package | Targets | Content |
| --- | --- | --- |
| `moonrockz/moon-lander-hosting` (`@hosting`) | all; `run` on `native` and `js`; `run_embedded` on `wasm` and `wasm-gc` | Builder, `command`, hosted services, `Host[S]`, `run`, `SignalProbe`, `run_embedded`, `Lifetime`, `StopToken`, `StopReason`, `SignalKind`, `StopRequested`, `ServiceName`, `ExitCode` and `HostError` |
| [`moonrockz/moon-lander-hosting/argparse`](argparse/README.mbt.md) (`@hosting_argparse`) | all | Command factory, global standard discovery flags, and the argparse types for the command (`Command`, `OptionArg`, `FlagArg` and others) |
| [`moonrockz/moon-lander-hosting/console`](console/README.mbt.md) (`@console`) | `native`, `js` | The console driver `run`: signals, the second signal and the process exit. A C signal stub on native, Node.js listeners on js |
| [`moonrockz/moon-lander-hosting/vendor/argparse`](vendor/README.md) | all | A copy of `moonbitlang/core/argparse` with `Command::try_parse`, until a pinned MoonBit release has it. Do not import it; use `@hosting_argparse` |

The [`moonrockz/moon-lander` guide](../lander/README.mbt.md) shows the full
pipeline, the name and exit-code rules, and `run`.

## Lifetime and stop requests

Every hook and command gets the same `Context[S]`. Its `lifetime` raises started
before the command, stopping before the stop hooks, and stopped after them.
Handlers are synchronous and cannot raise. Each event occurs at most once in a
run. A handler registered after its event runs at once, one time. Each new run
has its own lifetime, even when it uses the same host.

```mbt check
///|
test "register lifetime handlers from a hook" {
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.service("events", start=ctx => {
      ctx.lifetime.on_started(() => ())
      ctx.lifetime.on_stopping(() => {
        // Completed, Requested, Signal, Embedder, StartFailed or Failed.
        ignore(ctx.lifetime.stop_reason())
      })
      ctx.lifetime.on_stopped(() => ())
    })
    |> @hosting.build(_ => ())
  ignore(host)
}
```

`stop_application(exit_code?)` asks the host to stop. During start, the current
hook finishes; later start hooks and the command are skipped. Only services
that started get stop hooks. During the command, a request cancels its child
task. The command ends at its next suspension point and its `defer` blocks run
before the stop phase. Shutdown runs inside `@async.protect_from_cancel`.
A command can use the same function to protect a critical part of its work.

An enclosing desktop or application host uses `stop_from_embedder(exit_code?)`
from its shutdown callback. Capture the lifetime from a hook's public context.
The request follows the same cancellation and cleanup path, with reason
`Embedder`. It does not impersonate an OS signal or change an earlier stop reason.

```mbt check
///|
test "bind an enclosing shutdown callback from a public hook" {
  let shutdown : Ref[(() -> Unit)?] = Ref(None)
  let host = @hosting.builder(@lander_core.AppName::parse("desktop"), [])
    |> @hosting.service("shutdown", start=ctx => {
      shutdown.val = Some(() => ctx.lifetime.stop_from_embedder())
    })
    |> @hosting.build(_ => ())
  // The driver starts the host and registers the callback when this hook runs.
  ignore(host)
  assert_true(shutdown.val is None)
}
```

The first event that ends the run sets `stop_reason()`. Later requests keep that
reason and the first request's optional code, so all stop hooks read one reason.
`set_exit_code(code)` sets an application result without asking to stop.
The last call to `set_exit_code` or the first request's explicit code wins. A
signal or failure takes precedence over the application code. The driver returns
`RunOutcome` without ending the process.
`outcome.stop_reason()` exposes that run's actual final reason as a typed value.

## Cancellation checks

Use `ctx.cancelled()` to read the stop state, or `ctx.check_cancelled()` to raise
`StopRequested`. `ctx.lifetime.stop_token()` gives the same checks to code that
does not receive the context. These checks read stop requests, registered host
probes, and, on native and js, the current async task's cancellation state.
On native and js, read these checks inside an async task of the run.
Use `ctx.stop_requested()`, `ctx.lifetime.stop_requested()` or
`token.stop_requested()` in a synchronous foreign callback on the host thread,
including a JavaScript Promise or setTimeout callback. These methods poll the
same registered probes and read the retained host stop request. They return
false before a request, without querying a current task. They do not report
task-only cancellation, yield or run shutdown. Keep task-aware checks inside
an async task of the run. This API does not add cross-thread access guarantees.
Reading `stop_reason()` alone does not poll the probes.

```mbt check
///|
test "a foreign helper receives the shared host stop probe" {
  let command : @hosting.Hook[Unit] = ctx => {
    let token = ctx.lifetime.stop_token()
    let callback : () -> Bool = () => token.stop_requested()
    assert_false(callback())
    ctx.lifetime.stop_application()
    assert_true(callback())
  }
  ignore(command)
}
```

A probe stop reaches a suspended command only through the driver that owns the probe.
A command or hook that raises `StopRequested` ends as a stop and adds no failure.
A service whose starting or start hook raises it does not count as started.

```mbt check
///|
test "a command requests stop and polls its token" {
  let command : @hosting.Hook[Unit] = ctx => {
    let token = ctx.lifetime.stop_token()
    ctx.lifetime.stop_application(exit_code=@hosting.ExitCode::success())
    token.check_cancelled()
  }
  ignore(command)
}
```

On js, Node.js cannot deliver a signal listener while a synchronous loop keeps
running. Long synchronous loops must call `@async.pause()` at intervals to give
the event loop time to run the listener. A cancellation check alone does not
yield. On native, the console driver gives a signal probe that each check reads at
once, also in a loop that never yields. A task cancellation takes effect at a
suspension point.

A console driver gives `run` a `SignalProbe`. The run registers it before the
first hook, reads it in each cancellation check and every 50 ms, and changes the
first signal into a stop request with the reason `Signal(kind)`:

```mbt check
///|
test "a console driver gives the run a signal probe" {
  let signal : Ref[@hosting.SignalKind?] = Ref(None)
  // On native and js: @hosting.run(host, command, signals=probe)
  let probe = @hosting.SignalProbe::new(() => signal.val)
  ignore(probe)
}
```

```mbt check
///|
test "a long command yields between batches" {
  let command : @hosting.Hook[Unit] = ctx => {
    for _ in 0..<100 {
      ctx.check_cancelled()
      // Process one bounded batch here.
      @async.pause()
    }
  }
  ignore(command)
}
```

## Shutdown timeout

`shutdown_timeout(limit)` sets one budget for the full stop phase. The budget
starts when the command task has ended. The default is 30 s, and a later step
replaces an earlier value. Only native and js apply the limit. The wasm and
wasm-gc drivers have no timer.

`shutdown_timeout_key(key)` opts in to an application-named `@config.KeyPath`.
The host reads it once after loading and before the factory, through
`FromConfig` for `TimeLimit`. A value such as `"100ms"` overrides the builder
limit. An absent key keeps the builder limit, or the default 30 s. Invalid
text or a number gives a configuration error with code 2 before the
factory or any hook. The framework reserves no timeout key.

At the limit, the host cancels the current hook, skips the remaining stop hooks,
raises the stopped event and reports `ShutdownTimedOut`. A hook that protects
itself from cancellation, or does not yield, runs until it returns, and `run`
waits for it.

```mbt check
///|
test "set the shutdown timeout" {
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.shutdown_timeout(@lander_core.TimeLimit::seconds(5))
    |> @hosting.build(_ => ())
  ignore(host)
}
```

## Exit codes and reports

| Code | Cause |
| --- | --- |
| 0 | Clean run |
| 1 | Unhandled factory, hook or command failure; stop failure or timeout |
| 2 | Configuration or usage error in any phase |
| 130 | Interrupt signal stop |
| 143 | Terminate signal stop |
| 131 | Quit signal stop |
| n | Application code from `set_exit_code` or `stop_application(exit_code=...)` |

Precedence is signal, configuration or usage error, unhandled failure, stop
failure or timeout, application code, then 0. A later signal still sets the code
and keeps the first stop reason. Later stop requests keep the first request's
optional code. The last application code set by `set_exit_code` or the first
request wins. `ExitCode::from_int` accepts 0 to 255.

```mbt check
///|
test "application and signal codes" {
  let command : @hosting.Hook[Unit] = ctx => {
    ctx.lifetime.set_exit_code(@hosting.ExitCode::from_int(3))
    ctx.lifetime.stop_application(exit_code=@hosting.ExitCode::from_int(4))
  }
  assert_eq(@hosting.SignalKind::Interrupt.exit_code().to_int(), 130)
  ignore(command)
}
```

`run` reports each `ShutdownTimedOut` failure for every exit code, including
signal codes 130, 143 and 131. It reports other failures only for code 1 or 2.
Reports follow failure order. The default report writes one line to standard
error: `<application name>: <message>`. A run with no failures writes nothing,
including an application code of 1 or 2. `HostError`, `WorkingDirectoryError`,
`UsageError`, `FileTreeError`, `SuspendError`, `ShutdownTimedOut` and `ConfigError` use their `message()` text; other errors use
their `Show` text.

`error_report` replaces the default report. Its async callback gets each reported
failure in occurrence order with the final `ExitCode`, under the same rules.
It can write a custom format such as JSON. Each call to the builder step replaces
the earlier report.

```mbt check
///|
test "replace the failure report" {
  let reports : Array[(String, @hosting.ExitCode)] = []
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.error_report((error, code) => {
      let message = match error {
        @hosting.HostError::_ as e => e.message()
        @hosting.UsageError::_ as e => e.message()
        @hosting.ShutdownTimedOut::_ as e => e.message()
        _ => error.to_string()
      }
      reports.push((message, code))
    })
    |> @hosting.build(_ => ())
  let command : @hosting.Hook[Unit] = _ => raise @hosting.UsageError("expected a command")
  ignore((host, command))
}
```

## Starting settings and variables

Each run uses one variable set and one absolute working directory. The builder
accepts `env_vars`, `working_dir` and `environment` as starting settings. Omitted
variables and directory come from the process on native and js, or the empty
set and `/` on wasm and wasm-gc. Explicit values cause no process read.
`environment` is a parsed `@conventions.EnvironmentName` default and enables the
environments part of the host-owned conventions set, as does
`default_environment(name)`. Add `app_dirs()` or `conventions(f)` to supply that
set. Without it, the host gives a note; conventions added inside `configure`
keep their own environment settings. A bare builder with no environment default adds no discovery
reports and gives no discovery behavior to `--config` or `--project`. Parse the name at the
caller with `@conventions.EnvironmentName::parse`. The host takes the name from
`--environment`, then `<PREFIX>_ENVIRONMENT` in the run snapshot, then the default.
An invalid name ends the run with code 2 before the factory or any hook.

The factory, hooks and command read `environment.application_name`,
`environment.environment_name` and `environment.content_root` on their contexts.
The `is_environment(name)`, `is_development()`, `is_staging()` and
`is_production()` checks ignore case. With no name, each check gives false.
`content_root(path)` sets an absolute content root. Without it, the content root
is the working directory of the run. Windows paths use `/` separators.

A later `env_vars` or `working_dir` step replaces that setting. The factory,
hooks and command read the final values through `env_vars` and `working_dir`
on their contexts. The variable snapshot is an immutable
`@immut/sorted_map.SortedMap[String, String]` in deterministic key order.
Each builder step snapshots its input, so later changes to a caller map or
JSON object do not change the host. A missing process working directory ends
the run with `WorkingDirectoryError` and code 1 before any file read or hook.

```mbt check
///|
test "set the variable prefix and starting settings" {
  let host : @hosting.Host[Unit] = @lander_core.AppName::parse("my-tool")
    |> @hosting.builder([], env_vars={ "MT_LOG__FORMAT": "json" },
      working_dir=@lander_core.AbsolutePath::parse("/work"))
    |> @hosting.env_prefix(@lander_core.EnvPrefix::parse("MT"))
    |> @hosting.reserve_env(["MT_LOG_DIR"])
    |> @hosting.app_dirs()
    |> @hosting.build(_ => ())
  ignore(host)
}
```

The prefix defaults to the application name in upper case, with `-` changed to
`_`. An explicit prefix accepts only upper-case ASCII letters, digits and `_`,
starting with an upper-case letter or `_`. The host adds a variable source at priority 600 and reserves
`<PREFIX>_ENVIRONMENT`, `<PREFIX>_HOME` and the names from `reserve_env`.
`app_dirs()` gives the same name and final prefix to conventions.
`skip_env_source()` reports the source as skipped and keeps the variable set
for argparse and all other readers.

`env_vars` accepts a string map or a JSON object through `IntoEnvVars`. JSON
strings stay as written; other values become JSON text, except `null`, which
omits the variable. Nested objects stay whole and keys keep their spelling.
A non-object root ends the run with `UsageError` and code 2 before any file
read or hook.

`reserve_env` takes full variable names. The source compares names after it
converts each name to upper case. A later `env_prefix` step keeps these names as given; it
does not join them to the new prefix. For example, reserve `MT_TOKEN` when the
final prefix is `MT`:

```mbt check
///|
test "reserve a full name before changing the prefix" {
  let host : @hosting.Host[Unit] = @lander_core.AppName::parse("my-tool")
    |> @hosting.builder([], env_vars={ "MT_TOKEN": "secret" })
    |> @hosting.reserve_env(["MT_TOKEN"])
    |> @hosting.env_prefix(@lander_core.EnvPrefix::parse("MT"))
    |> @hosting.build(_ => ())
  ignore(host)
}
```

## Configuration and services

`configure(fn(sources) { ... })` adds formats and application sources through
`@config.ConfigBuilder`. Callbacks run in registration order after starting
settings, argument parsing and environment resolution. Sources merge in this
order: configure-callback sources in order, the host-owned conventions set
(System 100 through UserOverride 400), the `<PREFIX>_*` source at 600, then the
argparse overrides at 700 (group 14). Core has no builder trait, so use
`configure` for core steps.

Core load requires priorities that do not go down. With `app_dirs()` or
`conventions(f)`, a configure source must have priority 100 or less, such as
defaults or an in-memory value at 0. Put a file at a higher priority in the
conventions set, or leave out the host-owned set. A later change may order
sources by priority.

The run's variable set and working directory replace values that a callback
sets; use `env_vars` or `working_dir` on the host builder.

```mbt check
///|
test "configure application sources and conventions" {
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.configure(fn(sources) raise {
      sources
      |> @config.defaults({ "log": { "format": "text" } })
      |> @conventions.add(@conventions.app_dirs("acme"))
    })
    |> @hosting.build(_ => ())
  ignore(host)
}
```

A conventions set added inside `configure` keeps its own options. It does not
receive the standard host flags `--environment`, `--config`, `--isolated` and
`--project`, or the profile selectors. Use `app_dirs()` for the host-owned standard set and
`conventions(fn(c) { ... })` to change it. These steps compose in pipeline
order. A later `app_dirs()` replaces earlier convention parts. Without it,
`conventions` starts from an empty base set with the final host name and prefix.
The host-owned set receives the standard flags. For example,
`conventions(c => c |> @conventions.workspace())` after `app_dirs()` enables
workspace member selection with `--project`. With neither step, a bare host
adds no discovery reports.

Native and js call `@host.load` to answer file requests from disk, using the
run's variable snapshot and working directory. They ignore `files(tree)`.
On wasm and wasm-gc, `files(tree)` supplies the immutable snapshot to the pure
`@config.load`. A complete tree gives the configuration. An incomplete tree
raises `FileTreeError::IncompleteFileTree` with code 2 and preserves each
requested path and request kind. Its report names every path. `run_embedded`
ends with this code before the factory or any hook.

## Configuration profiles

Enable profiles with `profiles(policy)` after `app_dirs()`. Register
`profiles_option()` and `no_profiles_flag()` on the root argparse command.
Repeated `--profiles postgres,metrics` options concatenate in argument order.
`--no-profiles` conflicts with those options and disables includes, defaults,
groups and profile files. A bare builder adds no file discovery parts.

The host reserves the exact `<PREFIX>_PROFILES` selector from ordinary variable
mapping when its conventions enable profiles. A present empty or ASCII-whitespace
selector disables profiles; an absent selector does not. `env_prefix` sets this
prefix too. A custom profile provider inside `configure` keeps its own discovery
options; explicitly reserve its selector with `reserve_env`.

The factory, hooks and command read one recorded `config.profiles()` value.
Use a parsed `ProfileName` to query membership and choose services in the factory:

```mbt check
///|
test "choose a database service from recorded profile membership" {
  let postgres = @config.ProfileName::parse("postgres")
  let host : @hosting.Host[String] = @hosting.builder(
      @lander_core.AppName::parse("acme"), ["--profiles", "postgres"],
      env_vars=({} : Map[String, String]), working_dir=@lander_core.AbsolutePath::root())
    |> @hosting_argparse.command(name => @hosting_argparse.Command(name,
      options=[@hosting_argparse.profiles_option()],
      flags=[@hosting_argparse.no_profiles_flag()]))
    |> @hosting.configure(s => s |> @config.format(@toml.format()))
    |> @hosting.app_dirs()
    |> @hosting.profiles(@profiles.Policy::new())
    |> @hosting.service("database", start=ctx => {
      assert_eq(ctx.services == "postgres", ctx.config.profiles().contains(postgres))
    })
    |> @hosting.build(ctx =>
      if ctx.config.profiles().contains(postgres) { "postgres" } else { "memory" })
  ignore(host)
}
```

Profiles remain independent of `HostEnvironment`. A `Production` environment
does not activate `production`. Profile file layers have priority 380, after
environment files and before local and user overrides. Profile failures stop
before the factory with configuration exit code 2. Invalid CLI names and lists
give usage code 2 even when profiles are off. Help and version return before
configuration callbacks or profile discovery.

Custom source providers now return `Expansion::new(sources, warnings=notes)`
instead of a public struct literal. They can supply immutable resolution metadata
with its optional `profiles` argument. Providers that omit it keep state Off.
Exhaustive matches on `FileRole` must handle `ProfileFile(ProfileName)`.

After loading, the factory runs once. Its `BuildContext` and every hook's and
command's `Context[S]` share the final configuration, variable snapshot and
working directory. Each hook, lifetime handler and command uses the same
services record. Loading and timeout-decoding failures occur before the factory
or any hook. The public argparse overrides layer at priority 700 arrives in
task group 14.

## Embedded driver on wasm and wasm-gc

`run_embedded(host, command, stop_probe?)` is a synchronous driver for wasm and
wasm-gc. It needs no event loop, so any WebAssembly runtime can run the host.
It loads configuration from the `files(tree)` snapshot. With no `env_vars` or
`working_dir`, the variable set is empty and the working directory is `/`.
Hooks and the command run in the same order, with the same failure, stop-reason
and exit-code rules as `run`. The function returns a `RunOutcome` and does not
end the process.

Each hook and the command run until they return. They must not wait: a hook or
command that suspends fails with `SuspendError` and code 1, and the normal
failure and stop rules apply. The driver has no signals and no shutdown timeout.
The run stops through `stop_application` or through `stop_probe`. The host reads
the probe in each cancellation check and after each hook. When the probe gives
`true`, the run stops with the reason `Embedder`, and the stop phase runs.

The default report writes `<application name>: <message>` lines with `eprintln`.
On wasm, that is WASI standard error. On wasm-gc, core has no standard-error
channel, so the line goes to standard output; use `error_report` to send it to
a different place. A replacement report must not suspend. The driver ignores a
report that raises or suspends.

```mbt check
///|
test "prepare a host and a polling command for the embedded driver" {
  let stop = Ref(false)
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.files(@config.FileTree::new(complete=true))
    |> @hosting.build(_ => ())
  let command : @hosting.Hook[Unit] = ctx => {
    while !ctx.cancelled() {
      // Process one bounded batch here, without a wait.
      stop.val = true
    }
  }
  // On wasm and wasm-gc:
  // let outcome = @hosting.run_embedded(host, command, stop_probe=() => stop.val)
  ignore((host, command))
}
```
