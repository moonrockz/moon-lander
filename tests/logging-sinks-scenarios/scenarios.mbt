///|
/// The behavior of the logging test program. The parent process selects it
/// with the environment variable `LANDER_LOGGING_SCENARIO`, and gives an
/// absolute temporary directory in `LANDER_LOGGING_DIR`.
pub(all) enum Scenario {
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
pub async fn run(scenario : Scenario, dir : String) -> Unit {
  match scenario {
    Standalone => standalone(dir)
    Fanout => fanout(dir)
    Quiet => quiet(dir)
    Volume => volume(dir)
    _ => hosted(scenario, dir)
  }
}
