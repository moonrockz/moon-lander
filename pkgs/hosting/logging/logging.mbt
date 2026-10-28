///|
/// The time that the bridge gives each direct diagnostic line after the final
/// drain. A stalled standard error does not keep the process open longer.
let diagnostic_limit : Int = 1000

///|
/// Write `line` directly to standard error, outside the session, within
/// `diagnostic_limit`.
async fn diagnostic(line : String) -> Unit {
  ignore(
    @async.with_timeout_opt(diagnostic_limit, () => {
      ignore(@sink_runtime.write_diagnostic(line))
    }),
  )
}

///|
/// Whether the console destination of `settings` writes `Error` events to
/// standard error, so a default report line reaches the user through it.
fn reports_on_console(settings : @sinks.SessionSettings) -> Bool {
  settings.console() is Some(console) &&
  console.stream() is StandardError &&
  console.minimum() <= Error
}

///|
/// Whether the console destination of `report` writes to standard error and
/// has not failed.
fn console_healthy(report : @sinks.SessionReport) -> Bool {
  report
  .destinations()
  .iter()
  .any(destination => destination.target() is Console(StandardError) &&
    destination.failure() is None)
}

///|
/// The default report writer of the bridge: each line goes through the logger
/// as an `Error` event with the property `Failure`. The line also goes directly
/// to standard error, as without the bridge, when the console does not write
/// errors there, when the console destination failed, or when the session did
/// not accept the event, for example because its queue is full.
fn report_through(
  logger : &@lander_logging.Logger,
  settings : @sinks.SessionSettings,
  status : () -> @sinks.SessionReport,
) -> @hosting.ReportWriter {
  let console = reports_on_console(settings)
  async fn(line) {
    let before = status().accepted()
    logger.error("{Failure}", [Json::string(line)])
    let after = status()
    if !(console && after.accepted() > before && console_healthy(after)) {
      diagnostic(line)
    }
  }
}

///|
/// The finalizer of the bridge: close the session, which drains it within its
/// drain limit, then report all sink failures directly on standard error in one
/// write. A delivery failure turns an exit code 0 into 1; any other code stays.
async fn finalize(
  session : @sink_runtime.Session,
  selected : @hosting.ExitCode,
) -> @hosting.ExitCode {
  let report = session.close()
  let messages = report.failure_messages()
  if !messages.is_empty() {
    diagnostic(messages.join("\n"))
  }
  final_code(selected, report)
}

///|
/// The exit code after the final drain: code 1 when delivery failed after an
/// otherwise successful run, else the selected code.
fn final_code(
  selected : @hosting.ExitCode,
  report : @sinks.SessionReport,
) -> @hosting.ExitCode {
  if report.delivery_failed() && selected == @hosting.ExitCode::success() {
    @hosting.ExitCode::failure()
  } else {
    selected
  }
}

///|
/// Run a host as a console program with a logging session.
///
/// The bridge starts one session with `settings`, gives its logger to `host`,
/// which builds the host, and runs it with `@console.run`. The logger stays
/// open through the command, the stop hooks, the stopped event and the final
/// failure report. Without an application `error_report`, each default report
/// line also goes through the logger. Then, before the console driver ends the
/// process, the bridge closes the session. The close takes at most the drain
/// limit of `settings` (5 seconds by default) plus 1 second to stop the writer
/// and close the files after a drain timeout, and the direct report of sink
/// failures takes at most 1 more second. So after a stop request the process
/// can run for the shutdown timeout, plus the drain limit, plus 2 seconds. This also occurs after a configuration or start failure, after a
/// shutdown timeout and after a first signal. A second signal ends the process
/// at once, and records that are not written yet are lost.
///
/// Sink failures go directly to standard error, never through the failed
/// logger. A delivery failure after an otherwise successful run gives exit code
/// 1; a usage, failure or signal code stays.
///
/// When `host` raises, or the driver cannot install its signal handlers, the
/// session closes and the error passes out.
pub async fn[S] run(
  settings : @sinks.SessionSettings,
  host : (@sink_runtime.SessionLogger) -> @hosting.Host[S] raise,
  command : @hosting.Hook[S],
  observer? : (@sinks.SinkFailure) -> Unit,
) -> Unit {
  @sink_runtime.with_session(
    settings,
    observer?,
    session => {
      let logger = session.logger()
      let built = host(logger)
        |> @hosting.report_writer(
          report_through(logger, settings, () => session.status()),
        )
      @console.run(built, command, finalize=selected => finalize(session, selected))
    },
  )
}
