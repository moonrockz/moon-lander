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
