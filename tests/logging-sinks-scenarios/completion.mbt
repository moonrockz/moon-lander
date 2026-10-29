///|
pub(all) enum CompletionCase {
  Pending(@hosting.SignalKind)
  Startup(@hosting.SignalKind)
  Running(@hosting.SignalKind)
  Clean
  CommandFailure
  ConfigurationFailure
  ShutdownTimeout
  AlreadyClosed
  ReporterFailure(@hosting.SignalKind?)
  LegacyPending(@hosting.SignalKind)
  Unreported(@hosting.SignalKind)
}

///|
fn completion_reason(reason : @hosting.StopReason) -> String {
  match reason {
    Completed => "completed"
    Requested => "requested"
    Signal(_) => "signal"
    Embedder => "embedder"
    StartFailed(_) => "start-failed"
    Failed(_) => "failed"
  }
}

///|
async fn completion_hosted(mode : CompletionCase, dir : String) -> Unit {
  if mode is Unreported(kind) { completion_unreported(kind, dir); return }
  if mode is LegacyPending(kind) { completion_legacy(kind, dir); return }
  let settings = @sinks.SessionSettings::new(files=[
    @sinks.FileSink::new(directory(dir), stem("completion"), minimum=Trace),
  ])
  let pending : Ref[@hosting.SignalKind?] = Ref(match mode {
    Pending(kind) | ReporterFailure(Some(kind)) => Some(kind)
    _ => None
  })
  // Consume once so console retention is required through reporting.
  let probe = @hosting.SignalProbe::new(() => {
    let signal = pending.val
    pending.val = None
    signal
  })
  let captured : Ref[@sink_runtime.Session?] = Ref(None)
  let hooks = Ref(0)
  let commands = Ref(0)
  let diagnostic_started = Ref(false)
  let telemetry_stopped = Ref(false)
  @hosting_logging.run_with_session(settings, session => {
    captured.val = Some(session)
    let log : &@logging.Logger = session.logger()
    log.info("factory.accepted", [])
    let args = if mode is ConfigurationFailure { ["--invalid"] } else { [] }
    let builder = @hosting.builder(@lander_core.AppName::parse("completion"), args)
      |> @hosting.service("telemetry", start=_ => {
        hooks.val += 1
        log.info("telemetry.start", [])
        if mode is Startup(kind) { pending.val = Some(kind); @async.sleep(100) }
      }, stop=_ => {
        if diagnostic_started.val { assert_true(session.status().closed()) }
        telemetry_stopped.val = true
      })
      |> @hosting.service("diagnostic", start=_ => {
        hooks.val += 1
        diagnostic_started.val = true
        log.info("diagnostic.start", [])
      }, stop=_ => {
        if mode is ShutdownTimeout { @async.sleep(60000) }
        log.info("diagnostic.last", [])
        let report = session.close()
        assert_eq(report, session.close())
      })
    let builder = if mode is ShutdownTimeout {
      builder |> @hosting.shutdown_timeout(@lander_core.TimeLimit::millis(20))
    } else { builder }
    builder |> @hosting.build(_ => session.logger())
  }, ctx => {
    commands.val += 1
    (ctx.services : &@logging.Logger).info("command", [])
    match mode {
      Running(kind) => {
        defer (ctx.services : &@logging.Logger).info("command.cleanup", [])
        pending.val = Some(kind)
        @async.sleep(60000)
        fail("cancelled command resumed")
      }
      CommandFailure => fail("completion command failure")
      AlreadyClosed => ignore(captured.val.unwrap().close())
      _ => ()
    }
  }, signals=probe, completed=(outcome, selected) => {
    let report = captured.val.unwrap().status()
    assert_true(report.closed())
    assert_false(report.delivery_failed())
    for destination in report.destinations() { assert_eq(destination.written(), report.accepted()) }
    if diagnostic_started.val && !(mode is ShutdownTimeout) { assert_true(telemetry_stopped.val) }
    say("{\"reason\":\"\{completion_reason(outcome.stop_reason())}\",\"exit_code\":\{selected.to_int()},\"hooks\":\{hooks.val},\"commands\":\{commands.val},\"closed\":true}")
    if mode is ReporterFailure(_) { fail("completion reporter failed") }
  })
}

///|
/// Preserve the old clean-stop default when reporting is omitted.
async fn completion_unreported(kind : @hosting.SignalKind, dir : String) -> Unit {
  let settings = @sinks.SessionSettings::new(files=[
    @sinks.FileSink::new(directory(dir), stem("completion"), minimum=Trace),
  ])
  @hosting_logging.run_with_session(settings, session => {
    (session.logger() : &@logging.Logger).info("factory.accepted", [])
    @hosting.builder(@lander_core.AppName::parse("completion-default"), [])
    |> @hosting.service("must-not-start", start=_ => say("unexpected hook"))
    |> @hosting.build(_ => ())
  }, _ => say("unexpected command"), signals=@hosting.SignalProbe::new(() => Some(kind)))
}

///|
async fn completion_legacy(kind : @hosting.SignalKind, dir : String) -> Unit {
  let settings = @sinks.SessionSettings::new(files=[
    @sinks.FileSink::new(directory(dir), stem("completion"), minimum=Trace),
  ])
  let hooks = Ref(0)
  let commands = Ref(0)
  @hosting_logging.run(settings, logger => {
    (logger : &@logging.Logger).info("factory.accepted", [])
    @hosting.builder(@lander_core.AppName::parse("completion-legacy"), [])
    |> @hosting.service("must-not-start", start=_ => hooks.val += 1)
    |> @hosting.build(_ => ())
  }, _ => commands.val += 1, signals=@hosting.SignalProbe::new(() => Some(kind)), completed=(outcome, selected) => {
    say("{\"reason\":\"\{completion_reason(outcome.stop_reason())}\",\"exit_code\":\{selected.to_int()},\"hooks\":\{hooks.val},\"commands\":\{commands.val},\"legacy\":true}")
  })
}
