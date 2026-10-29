///|
/// The behavior of the logging test program. The parent process selects it
/// with the environment variable `LANDER_LOGGING_SCENARIO`, and gives an
/// absolute temporary directory in `LANDER_LOGGING_DIR`.
pub(all) enum Scenario {
  /// Application-owned result reporting after every returned outcome.
  Completion(CompletionCase)
  /// Hosted diagnostic close precedes telemetry; finalization repeats close.
  SessionOrdered
  /// Telemetry fails after diagnostic close; its report must bypass the logger.
  SessionLateFailure
  /// Diagnostic startup fails before its stop hook can run.
  SessionStartFailure
  /// A later service consumes the shutdown deadline before diagnostic close.
  SessionSkipped
  /// The diagnostic stop hook times out before it can close.
  SessionTimedStop
  /// A consuming signal probe stops the session-aware bridge.
  SessionSignal
  /// An external parent stops a worker that polls without yielding.
  SessionPoll
  /// The original logger-only bridge forwards an enclosing consuming probe.
  ProbeLegacy
  /// A sink failure during final drain must not replace the probe's signal code.
  ProbeFailure
  /// Both JSON property policies through public rolling sinks.
  ObjectProperties
  /// No host: one session writes three events to standard output, a text file
  /// and a JSON Lines file, closes, then writes `closed ...` directly.
  Standalone
  /// A host with the logging bridge: hooks and the command log, the run ends
  /// with 0.
  HostClean
  /// As `HostClean`, but the command logs `ready` and waits for a signal.
  HostWait
  /// As `HostWait`, and the `stop` hook of `b` logs `slow` and waits.
  HostSlowStop
  /// The command raises a usage error, so the default report is logged and the
  /// exit code is 2.
  HostUsage
  /// The `start` hook of `a` fails, so the command does not run.
  HostStartFailure
  /// The `stop` hook of `b` waits past a 200 ms shutdown timeout.
  HostTimeout
  /// The log directory is below a regular file, so the file destination fails
  /// and the console continues. The run itself succeeds.
  FileFailure
  /// Fan out to a Literate console and both file formats with a stepped clock,
  /// a small size limit, retention and a burst.
  Fanout
  /// A file destination for `Error` and an `Information` event only, so no
  /// file event occurs. The log directory is `<dir>/never`.
  Quiet
  /// `volume_events` events to the console and a text file, more than one pipe
  /// buffer, with a drain after each `volume_batch` events so none is dropped.
  Volume
  /// An unknown argument fails the configuration before any hook runs.
  HostConfigFailure
}

///|
/// The scenario named by `text`, or `None` for an unknown name.
pub fn Scenario::parse(text : String) -> Scenario? {
  match text {
    "completion-early-int" => Some(Completion(Pending(Interrupt)))
    "completion-early-term" => Some(Completion(Pending(Terminate)))
    "completion-startup" => Some(Completion(Startup(Terminate)))
    "completion-running" => Some(Completion(Running(Interrupt)))
    "completion-clean" => Some(Completion(Clean))
    "completion-failure" => Some(Completion(CommandFailure))
    "completion-config" => Some(Completion(ConfigurationFailure))
    "completion-timeout" => Some(Completion(ShutdownTimeout))
    "completion-closed" => Some(Completion(AlreadyClosed))
    "completion-throws" => Some(Completion(ReporterFailure(None)))
    "completion-throws-int" => Some(Completion(ReporterFailure(Some(Interrupt))))
    "completion-throws-term" => Some(Completion(ReporterFailure(Some(Terminate))))
    "completion-legacy-int" => Some(Completion(LegacyPending(Interrupt)))
    "completion-legacy-term" => Some(Completion(LegacyPending(Terminate)))
    "completion-default-int" => Some(Completion(Unreported(Interrupt)))
    "completion-default-term" => Some(Completion(Unreported(Terminate)))
    "session-ordered" => Some(SessionOrdered)
    "session-late-failure" => Some(SessionLateFailure)
    "session-start-failure" => Some(SessionStartFailure)
    "session-skipped" => Some(SessionSkipped)
    "session-timed-stop" => Some(SessionTimedStop)
    "session-signal" => Some(SessionSignal)
    "session-poll" => Some(SessionPoll)
    "probe-legacy" => Some(ProbeLegacy)
    "probe-failure" => Some(ProbeFailure)
    "object-properties" => Some(ObjectProperties)
    "standalone" => Some(Standalone)
    "host-clean" => Some(HostClean)
    "host-wait" => Some(HostWait)
    "host-slow-stop" => Some(HostSlowStop)
    "host-usage" => Some(HostUsage)
    "host-start-failure" => Some(HostStartFailure)
    "host-timeout" => Some(HostTimeout)
    "file-failure" => Some(FileFailure)
    "fanout" => Some(Fanout)
    "quiet" => Some(Quiet)
    "volume" => Some(Volume)
    "host-config-failure" => Some(HostConfigFailure)
    _ => None
  }
}

///|
/// The count of events in the burst of `Fanout`.
pub let burst_events : Int = 500

///|
/// The outstanding record limit of `Fanout`.
pub let burst_limit : Int = 64

///|
fn absolute(text : String) -> @lander_core.AbsolutePath {
  @lander_core.AbsolutePath::parse(text) catch {
    error => abort("LANDER_LOGGING_DIR must be absolute: \{error.message()}")
  }
}

///|
fn directory(text : String) -> @sinks.LogDirectory {
  @sinks.LogDirectory::from_absolute(absolute(text)) catch {
    error => abort("bad log directory: \{error.message()}")
  }
}

///|
fn stem(text : String) -> @rolling.LogFileStem {
  @rolling.LogFileStem::parse(text) catch {
    error => abort("bad stem: \{error.message()}")
  }
}

///|
/// A plain console on standard output for every level, so the parent reads
/// the log lines from the child output.
fn plain_console() -> @sinks.ConsoleSink {
  @sinks.ConsoleSink::new(stream=StandardOutput, minimum=Trace, color=Never)
}

///|
fn settings(
  console : @sinks.ConsoleSink,
  files : Array[@sinks.FileSink],
  event_limit? : Int = 1024,
) -> @sinks.SessionSettings {
  @sinks.SessionSettings::new(
    console~,
    files~,
    event_limit=@sinks.QueueEventLimit::count(event_limit),
  ) catch {
    error => abort("bad settings: \{error.message()}")
  }
}

///|
priv suberror CompilerError {
  CompilerError(String)
}

///|
impl Show for CompilerError with output(self, logger) {
  let CompilerError(text) = self
  logger.write_string(text)
}

///|
/// Write `line` directly to standard output, outside every session.
async fn say(line : String) -> Unit {
  ignore(@sink_runtime.write_diagnostic(line, stream=StandardOutput))
}

///|
/// The text of a report for the parent: `accepted=N queue_full=N failed=B`.
fn report_text(report : @sinks.SessionReport) -> String {
  let dropped = report.dropped()
  let written = report.destinations().map(d => d.written().to_string())
  "accepted=\{report.accepted()} queue_full=\{dropped.queue_full()} failed=\{report.delivery_failed()} written=\{written.join(",")}"
}

///|
async fn standalone(dir : String) -> Unit {
  let logs = directory(dir)
  let settings = settings(plain_console(), [
    @sinks.FileSink::new(logs, stem("acme"), minimum=Trace),
    @sinks.FileSink::new(logs, stem("acme"), format=JsonLines, minimum=Trace),
  ])
  let report = @sink_runtime.with_session(settings, session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("Loaded {Count} files from {Path}", [Json(3), Json("src")])
    logger.warn("Unicode {Text}", [Json("é 😀 ✓")])
    logger.error(
      "Compilation failed for {File}",
      [Json("app.mbt")],
      error=CompilerError(
        "CompilerError: Unknown identifier calculate_total\n  at app.mbt:42",
      ),
    )
    session.close()
  })
  say("closed " + report_text(report))
}

///|
async fn object_properties(dir : String) -> Unit {
  let logs = directory(dir)
  let limit = @rolling.FileByteLimit::bytes(1L) catch { error => abort(error.message()) }
  let settings = settings(plain_console(), [
    @sinks.FileSink::new(logs, stem("array"), format=JsonLines, policy=Size(limit), retention=KeepAll),
    @sinks.FileSink::new(logs, stem("named"), format=JsonLines, json_properties=NamedObject, policy=Size(limit), retention=KeepAll),
  ])
  let report = @sink_runtime.with_session(settings, session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("{path} {array} {object} {nothing} {flag} {number}", [
      "/repo/morphir.toml", [1, Json::null(), { "nested": true }],
      { "items": [false, 2] }, Json::null(), true, 2.5,
    ])
    logger.info("{path} {level} {path} {command} {path} {level} {duplicateProperties} {properties}", [
      Json::null(), "event", [1, Json::null()], "project.list",
      { "nested": [true, 2] }, false, "inside", "safe",
    ])
    ignore(session.drain())
    logger.info("{value} {value} {text}", [1, Json::null(), "é 😀\n\r\u{1b}\"\\"])
    logger.info("empty", [])
    session.close()
  })
  say("closed " + report_text(report))
}

///|
async fn quiet(dir : String) -> Unit {
  let settings = settings(plain_console(), [
    @sinks.FileSink::new(directory(dir + "/never"), stem("acme"), minimum=Error),
  ])
  let report = @sink_runtime.with_session(settings, session => {
    (session.logger() : &@logging.Logger).info("only on the console", [])
    session.close()
  })
  say("closed " + report_text(report))
}

///|
/// The count of events of `Volume`.
pub let volume_events : Int = 4000

///|
/// The events of `Volume` between two drains: less than the default queue.
pub let volume_batch : Int = 500

///|
/// The message of event `index` of `Volume`: 72 characters.
pub fn volume_line(index : Int) -> String {
  let number = index.to_string()
  "line=" + "0".repeat(6 - number.length()) + number + " " + "x".repeat(60)
}

///|
async fn volume(dir : String) -> Unit {
  let settings = settings(plain_console(), [
    @sinks.FileSink::new(directory(dir), stem("volume"), minimum=Trace),
  ])
  let report = @sink_runtime.with_session(settings, session => {
    let logger : &@logging.Logger = session.logger()
    for index in 0..<volume_events {
      logger.info("{Line}", [Json(volume_line(index))])
      if (index + 1) % volume_batch == 0 {
        ignore(session.drain())
      }
    }
    session.close()
  })
  say("closed " + report_text(report))
}

///|
/// The host of the host scenarios. Each hook logs its name through the
/// session logger.
fn host(
  scenario : Scenario,
  logger : @sink_runtime.SessionLogger,
) -> @hosting.Host[@sink_runtime.SessionLogger] raise {
  let log : &@logging.Logger = logger
  let hook = (name : String) => log.info("hook={Name}", [Json(name)])
  let args = if scenario is HostConfigFailure { ["--bogus"] } else { [] }
  let builder = @hosting.builder(
      @lander_core.AppName::parse("logging-host"),
      args,
    )
    |> @hosting.service(
      "a",
      starting=_ => hook("a.starting"),
      start=_ => {
        hook("a.start")
        if scenario is HostStartFailure {
          fail("a cannot start")
        }
      },
      started=_ => hook("a.started"),
      stopping=_ => hook("a.stopping"),
      stop=_ => hook("a.stop"),
      stopped=_ => hook("a.stopped"),
    )
    |> @hosting.service(
      "b",
      stopping=_ => hook("b.stopping"),
      stop=_ => {
        hook("b.stop")
        if scenario is (HostSlowStop | HostTimeout) {
          log.info("slow", [])
          @async.sleep(60000)
          hook("b.stop.end")
        }
      },
      stopped=_ => hook("b.stopped"),
    )
  let builder = if scenario is HostTimeout {
    builder |> @hosting.shutdown_timeout(@lander_core.TimeLimit::millis(200))
  } else {
    builder
  }
  builder |> @hosting.build(_ => logger)
}

///|
async fn hosted(scenario : Scenario, dir : String) -> Unit {
  let logs = if scenario is FileFailure {
    directory(dir + "/blocker/logs")
  } else {
    directory(dir)
  }
  let settings = settings(plain_console(), [
    @sinks.FileSink::new(logs, stem("host"), minimum=Trace),
  ])
  @hosting_logging.run(settings, logger => host(scenario, logger), ctx => {
    let log : &@logging.Logger = ctx.services
    match scenario {
      HostUsage => raise @hosting.UsageError("bad option")
      HostWait | HostSlowStop => {
        log.info("ready", [])
        @async.sleep(60000)
        log.info("command must be cancelled", [])
      }
      _ => log.info("command", [])
    }
  })
}

///|
fn stop_reason(reason : @hosting.StopReason?) -> String {
  match reason {
    Some(Signal(Interrupt)) => "Signal(Interrupt)"
    Some(Signal(Terminate)) => "Signal(Terminate)"
    Some(Signal(Quit)) => "Signal(Quit)"
    Some(Completed) => "Completed"
    Some(StartFailed(_)) => "StartFailed"
    _ => "other"
  }
}

///|
async fn session_hosted(
  scenario : Scenario,
  dir : String,
  signals? : @hosting.SignalProbe,
) -> Unit {
  let console = if scenario is SessionLateFailure {
    @sinks.ConsoleSink::new()
  } else { plain_console() }
  let settings = settings(console, [
    @sinks.FileSink::new(directory(dir), stem("session"), minimum=Trace),
  ])
  let pending : Ref[@hosting.SignalKind?] = Ref(None)
  let probe = signals.unwrap_or(@hosting.SignalProbe::new(() => {
    let value = pending.val
    pending.val = None
    value
  }))
  let polled = Ref(false)
  @hosting_logging.run_with_session(settings, session => {
    let log : &@logging.Logger = session.logger()
    let builder = @hosting.builder(@lander_core.AppName::parse("session-host"), [])
      |> @hosting.service("telemetry", start=_ => {
        say("telemetry=start")
        log.info("telemetry.start", [])
      }, stop=ctx => {
        if scenario is (SessionOrdered | SessionLateFailure | SessionSignal | SessionPoll) {
          let report = session.status()
          assert_true(report.closed())
          assert_false(report.delivery_failed())
          for destination in report.destinations() {
            assert_eq(destination.written(), report.accepted())
          }
          assert_eq(report.dropped().closed(), 1L)
          say("telemetry=flushed-after-drain")
        }
        say("reason=" + stop_reason(ctx.lifetime.stop_reason()))
        say("telemetry=stop")
        if scenario is SessionLateFailure { fail("telemetry flush failed") }
      })
      |> @hosting.service("diagnostic", start=_ => {
        log.info("diagnostic.start", [])
        say("diagnostic=start")
        if scenario is SessionStartFailure { fail("diagnostic startup failed") }
      }, stop=ctx => {
        say("diagnostic=stop")
        say("reason=" + stop_reason(ctx.lifetime.stop_reason()))
        if polled.val { say("polled=true") }
        log.info("diagnostic.last", [])
        if scenario is SessionTimedStop { @async.sleep(60000) }
        let first = session.close()
        assert_eq(first, session.close())
        assert_true(first.closed())
        assert_false(first.delivery_failed())
        // A direct event after close is rejected and counted, not admitted.
        let memory = @logging.MemoryLogger::new()
        (memory : &@logging.Logger).info("late-after-close", [])
        session.logger().log(memory.events()[0])
        say("diagnostic=closed")
      }, stopped=_ => log.info("late-stopped", []))
    let builder = if scenario is SessionSkipped {
      builder |> @hosting.service("blocker", stop=_ => {
        log.info("blocker.stop", [])
        say("blocker=stop")
        @async.sleep(60000)
      })
    } else { builder }
    let builder = if scenario is (SessionSkipped | SessionTimedStop) {
      builder |> @hosting.shutdown_timeout(@lander_core.TimeLimit::millis(100))
    } else { builder }
    builder |> @hosting.build(_ => session.logger())
  }, ctx => {
    (ctx.services : &@logging.Logger).info("command", [])
    if scenario is SessionSignal { pending.val = Some(Terminate) }
    if scenario is (SessionSignal | SessionPoll) {
      // No async operation between ready and the first cancellation read.
      println("ready")
      let count = Ref(0UL)
      while !ctx.cancelled() { count.val += 1UL }
      polled.val = true
    }
  }, signals=probe)
}

///|
async fn legacy_probe(dir : String, failed_sink~ : Bool) -> Unit {
  let pending : Ref[@hosting.SignalKind?] = Ref(None)
  let settings = settings(plain_console(), [
    @sinks.FileSink::new(directory(if failed_sink { dir + "/blocker/logs" } else { dir }), stem("legacy")),
  ])
  @hosting_logging.run(settings, logger => {
    @hosting.builder(@lander_core.AppName::parse("legacy-probe"), [])
    |> @hosting.service("diagnostic", stop=ctx => {
      (logger : &@logging.Logger).info("reason={Reason}", [Json(stop_reason(ctx.lifetime.stop_reason()))])
    })
    |> @hosting.build(_ => logger)
  }, ctx => {
    (ctx.services : &@logging.Logger).info("legacy.accepted", [])
    pending.val = Some(Interrupt)
    while !ctx.cancelled() { () }
  }, signals=@hosting.SignalProbe::new(() => {
    let value = pending.val
    pending.val = None
    value
  }))
}

///|
/// 2026-10-27T23:59:58.000Z, the first time of `Fanout`.
pub let fanout_day_one : Int64 = 1793145598000L

///|
/// 2026-10-28T00:00:01.000Z, the second time of `Fanout`.
pub let fanout_day_two : Int64 = 1793145601000L

///|
fn timestamp(millis : Int64) -> @formatting.LogTimestamp {
  @formatting.LogTimestamp::from_epoch_millis(millis) catch {
    error => abort("bad sample time: \{error.message()}")
  }
}

///|
/// Fan out to a Literate console, a text file with a 400-byte size limit and
/// the newest 3 files, and a daily JSON Lines file that keeps all files. A
/// stepped clock moves from 2026-10-27 to 2026-10-28. A synchronous burst of
/// `burst_events` events meets a queue of `burst_limit` records.
async fn fanout(dir : String) -> Unit {
  let logs = directory(dir)
  let now = Ref(fanout_day_one)
  let text_limit = @rolling.FileByteLimit::bytes(400L) catch {
    error => abort("\{error.message()}")
  }
  let keep = @rolling.RetainedFileCount::count(3) catch {
    error => abort("\{error.message()}")
  }
  let settings = settings(
    @sinks.ConsoleSink::new(stream=StandardOutput, color=Always),
    [
      @sinks.FileSink::new(
        logs,
        stem("acme"),
        policy=Size(text_limit),
        retention=KeepNewest(keep),
        minimum=Debug,
      ),
      @sinks.FileSink::new(
        logs,
        stem("acme"),
        format=JsonLines,
        policy=Daily,
        retention=KeepAll,
      ),
    ],
    event_limit=burst_limit,
  )
  let report = @sink_runtime.with_session(
    settings,
    clock=() => timestamp(now.val),
    session => {
      let logger : &@logging.Logger = session.logger()
      logger.debug("Only in the text file", [])
      logger.info("Loaded {Count} files from {Path}", [Json(3), Json("src")])
      ignore(session.drain())
      now.val = fanout_day_two
      logger.info("Next day {Day} with {Flag} and {Nothing}", [
        Json(28),
        Json(true),
        Json::null(),
      ])
      ignore(session.drain())
      for index in 0..<burst_events {
        logger.info("burst {Index}", [Json(index)])
      }
      session.close()
    },
  )
  say("closed " + report_text(report))
}

///|
/// Run the scenario. On native a host scenario ends the process inside the
/// console driver; on js it ends when the event loop is empty.
pub async fn run(scenario : Scenario, dir : String, signals? : @hosting.SignalProbe) -> Unit {
  match scenario {
    Completion(mode) => completion_hosted(mode, dir)
    SessionOrdered | SessionLateFailure | SessionStartFailure | SessionSkipped | SessionTimedStop |
    SessionSignal | SessionPoll => session_hosted(scenario, dir, signals?)
    ProbeLegacy => legacy_probe(dir, failed_sink=false)
    ProbeFailure => legacy_probe(dir, failed_sink=true)
    ObjectProperties => object_properties(dir)
    Standalone => standalone(dir)
    Fanout => fanout(dir)
    Quiet => quiet(dir)
    Volume => volume(dir)
    _ => hosted(scenario, dir)
  }
}
