# moonrockz/moon-lander-hosting/logging

The opt-in bridge between a console host and a logging session, on `native` and
`js`. `run` starts one session of
[`moonrockz/moon-lander-logging-hosting-async`](../../logging-hosting-async/README.mbt.md),
gives its logger to the code that builds the host, runs the host with the console
driver, and drains the session before the process ends.

The bridge has no sinks of its own. The console and file destinations, the bounded
queue and the writer task are in the lower module, which an application can also use
without a host.

```mbt check
///|
/// The body of `async fn main` in a console program that logs to standard error
/// and to rolling files in `/var/log/acme`.
async fn logging_main() -> Unit {
  let logs = "/var/log/acme"
    |> @lander_core.AbsolutePath::parse
    |> @sinks.LogDirectory::from_absolute
  let settings = @sinks.SessionSettings::new(
    console=@sinks.ConsoleSink::new(),
    files=[@sinks.FileSink::new(logs, @rolling.LogFileStem::parse("acme"))],
  )
  @hosting_logging.run(
    settings,
    logger => {
      let log : &@lander_logging.Logger = logger
      @hosting.builder(@lander_core.AppName::parse("acme"), [])
      |> @hosting.service("worker", stopped=_ => log.info("worker stopped", []))
      |> @hosting.build(_ => logger)
    },
    ctx => {
      let log : &@lander_logging.Logger = ctx.services
      log.info("Started {Name}", [Json::string("acme")])
      while !ctx.cancelled() {
        @async.sleep(100)
      }
    },
  )
}

///|
test "the bridge example compiles" {
  // The console driver ends the process, so this test does not call it.
  ignore(logging_main)
}
```

## What runs when

| Step | Logging |
| --- | --- |
| Configuration load, factory, start hooks | The logger is open |
| Command | The logger is open |
| Stop hooks and the stopped event | The logger is open |
| Failure report | Without an application `error_report`, each default line `<name>: <message>` is an `Error` event with the property `Failure` |
| Final drain | The bridge closes the session: it drains the accepted records within the drain limit, closes the files and deletes their ownership markers |
| Sink failures | All failures go directly to standard error in one write, as `logging: <operation> failed for <target>...`, never through the failed logger |
| Process end | Native: libc `exit`. js: the driver sets `process.exitCode` |

The bridge drains also after a configuration or start failure, after a shutdown
timeout that skipped hooks, and after a first signal. It is not a stop hook, so a
skipped hook cannot skip it.

The bridge also writes the default report line directly to standard error, as the
host does without the bridge, when no console destination writes `Error` events
there, when that console destination failed, or when the session did not accept the
event (for example, a full queue).
An application `error_report` keeps its behavior; it can log through the same logger.

## Exit codes and time limits

A delivery failure after an otherwise successful run gives exit code 1. A delivery
failure is a destination that failed, a record that stayed undelivered, or a drain
that used its full time limit. A usage, failure or signal code from the run stays.

The final drain runs protected from the first signal and has its own limit, 5 seconds
by default (`drain_limit` of the settings). When the drain uses its full limit, the
session gives the stopped writer and the files at most 1 more second, and the direct
report of sink failures takes at most 1 more second. After a stop request, the
process can run for the shutdown timeout of the host, plus the drain limit, plus 2
seconds. A second signal ends the
process at once, as without the bridge. Records that are not written yet are then
lost; the bridge gives no delivery guarantee for a forced end.

Run one bridge in a process: the console driver installs global signal handlers.
