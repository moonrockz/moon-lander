# moonrockz/moon-lander-hosting

The host of a Moon-Lander application. A host builder holds the application
name, the arguments, the hosted services and a services factory. `build` gives a
`Host`, and `run` starts the services, runs the command and stops the services in
a known order, with a clear exit code. Each run has a lifetime for events,
stop requests and cancellation checks. Arguments, signals and host configuration
are later parts of `add-host-lifecycle`.

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
| `moonrockz/moon-lander-hosting` (`@hosting`) | all; `run` on `native` and `js` | Builder, hosted services, `Host[S]`, `run`, `Lifetime`, `StopToken`, `StopReason`, `SignalKind`, `StopRequested`, `ServiceName`, `ExitCode` and `HostError` |
| `moonrockz/moon-lander-hosting/console` (`@console`) | `native` | The C signal stub for SIGINT, SIGTERM and SIGQUIT, and the Windows console events |

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

The first event that ends the run sets `stop_reason()`. Later requests keep that
reason and the first request's optional code, so all stop hooks read one reason.
`set_exit_code(code)` sets an application result without asking to stop. A raised
failure still gives code 1. The driver returns `RunOutcome` without ending the
process.

## Cancellation checks

Use `ctx.cancelled()` to read the stop state, or `ctx.check_cancelled()` to raise
`StopRequested`. `ctx.lifetime.stop_token()` gives the same checks to code that
does not receive the context. These checks read stop requests, registered host
probes, and, on native and js, the current async task's cancellation state.
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
yield. On native, synchronous loops can poll host signal probes, but a task
cancellation still takes effect at a suspension point.

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
