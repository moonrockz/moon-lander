# moonrockz/moon-lander-hosting/console

The console driver of a Moon-Lander host, on `native` and `js`. `run` runs a host
with `@hosting.run`, changes console signals into a graceful stop, and ends the
process with the exit code of the run. Use it in `async fn main`:

```mbt check
///|
/// The body of `async fn main` in a console program.
async fn console_main() -> Unit {
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.service("worker", stop=_ => println("worker stopped"))
    |> @hosting.build(_ => ())
  @console.run(host, ctx => {
    while !ctx.cancelled() {
      @async.sleep(100)
    }
  })
}

///|
test "the console example compiles" {
  // The driver ends the process, so this test does not call it.
  ignore(console_main)
}
```

## Finalize before the process ends

`finalize` runs one time after the run and its failure reports, before the native
driver calls libc `exit` and before the js driver sets `process.exitCode`. It also
runs after a configuration or start failure, after a shutdown timeout that skipped
hooks, and after a first signal. It gets the selected exit code and gives the code
to use, protected from cancellation. A second signal still ends the process at once.
A signal that arrives while it runs selects the signal code. When `finalize` raises,
a selected code 0 becomes 1 and any other code stays. The logging bridge
`moonrockz/moon-lander-hosting/logging` uses it to drain its session.

```mbt check
///|
async fn console_with_finalizer() -> Unit {
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.build(_ => ())
  // Flush application output in the finalizer, then keep the selected code.
  @console.run(host, _ => (), finalize=selected => selected)
}

///|
test "the finalizer example compiles" {
  ignore(console_with_finalizer)
}
```

## Signals

| Platform | Signal or event | Stop reason | Exit code |
| --- | --- | --- | --- |
| Linux, macOS | SIGINT | `Signal(Interrupt)` | 130 |
| Linux, macOS | SIGTERM | `Signal(Terminate)` | 143 |
| Linux, macOS | SIGQUIT | `Signal(Quit)` | 131 |
| Windows native | `CTRL_C_EVENT` | `Signal(Interrupt)` | 130 |
| Windows native | `CTRL_CLOSE_EVENT` | `Signal(Terminate)` | 143 |
| Windows native | `CTRL_BREAK_EVENT` | `Signal(Quit)` | 131 |
| Windows js | SIGINT (Ctrl-C) | `Signal(Interrupt)` | 130 |
| Windows js | SIGHUP (console close) | `Signal(Terminate)` | 143 |
| Windows js | SIGBREAK (Ctrl-Break) | `Signal(Quit)` | 131 |

The first signal is a stop request. The run cancels the command task at its next
suspension point and runs all stop hooks of the started services. A second signal
ends the process at once with its own exit code. No later hook or event runs.
SIGHUP on Linux and macOS keeps its default action.

On native, a C signal stub records the signal. Each cancellation check
(`ctx.cancelled()`, `ctx.check_cancelled()` or a `StopToken`) reads it at once, also
in a loop that never suspends. A watcher task reads it every 50 ms and cancels the
command task. The second signal ends the process from inside the handler, so it
also works during a loop with no suspension point and no check. After the stop
phase, the driver ends the process through libc `exit`.

On js, Node.js and Bun call the listeners only when the JavaScript stack is empty.
A long synchronous loop must call `@async.pause()` to let a listener run (see the
`moonrockz/moon-lander-hosting` README). After the stop phase, the driver removes
its listeners and sets `process.exitCode`. It does not call `process.exit` at
once, so Node.js writes all output that is still in a pipe before the process
ends. After a signal stop, a timer that does not keep the event loop open ends
the process with `process.exit` 2 seconds later, if a timer or socket that a
service left open still keeps it running.

The handlers are global state. Run only one console host in a process. When the
driver cannot install its handlers, `run` raises `SignalHandlersUnavailable` before
it reads configuration or runs a hook.

## Enclosing signal owner

Pass `signals` when a launcher owns signal delivery. The driver installs no OS
handlers or listeners and removes none owned by the launcher. On native it turns
off the async runtime's cancellation signal mask. The launcher owns second-signal
escalation. Repeated reads of one signal do not count as new signals. Each run
retains its first observed signal through cleanup and finalization, even when
the reader consumes its flag. Keep the reader cheap and non-raising.

```mbt check
///|
async fn console_with_owner(probe : @hosting.SignalProbe) -> Unit {
  let host : @hosting.Host[Unit] = "acme"
    |> @lander_core.AppName::parse
    |> @hosting.builder([])
    |> @hosting.build(_ => ())
  @console.run(host, ctx => {
    while !ctx.cancelled() {
      @async.pause()
    }
  }, signals=probe)
}

///|
test "the enclosing owner example compiles" {
  ignore(console_with_owner)
}
```

A Node parent can record SIGINT or SIGTERM in shared memory while its worker is
busy. A probe that reads that memory lets `ctx.cancelled()` or
`ctx.check_cancelled()` see the signal without yielding.
For synchronous foreign callbacks on the host thread, use
`ctx.stop_requested()` or `ctx.lifetime.stop_token().stop_requested()`. These
checks poll the same probe without a current-task query. The parent must remain
able to receive signals and decide when a second signal ends the worker.

## Windows console events

A program can send only `CTRL_BREAK_EVENT` to one process group. The acceptance
tests send it to native, Node.js and Bun child processes. `CTRL_C_EVENT` goes to
every process on the console, also the test runner, and no API sends
`CTRL_CLOSE_EVENT`. A unit test covers the mapping of these two events in the
handler of the stub. Do these manual checks on Windows before a release:

1. Start a console program that uses `run` in a console window. Push Ctrl-C. Make
   sure that the stop hooks run and the exit code (`echo %ERRORLEVEL%` in `cmd`,
   `$LASTEXITCODE` in PowerShell) is 130.
2. Start the program again in its own console window. Close the window. Make sure
   that the stop hooks run, for example with a stop hook that writes a file.
3. Push Ctrl-C two times while a stop hook waits. Make sure that the process ends
   at once with 130.

### Console close time limit

After `CTRL_CLOSE_EVENT`, Windows ends the process when the system time limit
ends: about 5 seconds for a native program, and about 10 seconds for Node.js
(Node.js documentation of SIGHUP). The handler
waits, so the stop phase can run, but the host cannot make the limit longer. Keep
the stop phase after a console close shorter than this limit. The shutdown timeout
of the host does not change the system limit.

## Completion reporting

The optional `completed` callback has type `Completion`, an async function from
`RunOutcome` and selected `ExitCode` to `Unit`. It runs once after the host's
failure reports and optional `finalize`, before native exit or the JS exit-code
selection. This includes a pending signal before every service hook and command.
The logging bridge forwards the same option after its session finalizer.

The callback is protected from cancellation. If it raises, success becomes 1 and
an existing nonzero code remains. A signal observed during reporting still selects
its signal code. The callback's selected code is a snapshot at entry; callback
failure or a later signal can change process exit. Applications own their output
schema, partial writes and callback time budget. Pre-run factory or signal-setup
exceptions retain their existing contract. Existing callers can omit the option.
