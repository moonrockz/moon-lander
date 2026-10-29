///|
async test "session-aware factory failure still closes and drains its real session" {
  let captured : Ref[@sink_runtime.Session?] = Ref(None)
  let failed = try {
    run_with_session(
      @sinks.SessionSettings::standard(),
      session => {
        captured.val = Some(session)
        (session.logger() : &@lander_logging.Logger).info("before factory failure", [])
        fail("factory failed")
      },
      (_ : @hosting.Context[Unit]) => (),
      signals=@hosting.SignalProbe::new(() => None),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  let report = captured.val.unwrap().status()
  assert_true(report.closed())
  assert_eq(report.accepted(), 1L)
  assert_eq(report.destinations()[0].written(), 1L)
}

///|
fn report(failed~ : Bool) -> @sinks.SessionReport raise {
  @sinks.SessionReport::new(
    accepted=1L,
    dropped=@sinks.DropCounts::new(
      queue_full=0L,
      oversized=0L,
      closed=0L,
      reentrant=0L,
    ),
    destinations=[
      @sinks.DestinationReport::new(
        Console(StandardError),
        written=if failed { 0L } else { 1L },
        undelivered=if failed { 1L } else { 0L },
      ),
    ],
    drain_timed_out=false,
    closed=true,
  )
}

///|
test "a delivery failure turns only a success into exit code 1" {
  let success = @hosting.ExitCode::success()
  assert_eq(final_code(success, report(failed=false)), success)
  assert_eq(final_code(success, report(failed=true)), @hosting.ExitCode::failure())
  for code in [1, 2, 130, 143, 131, 7] {
    let selected = @hosting.ExitCode::from_int(code)
    assert_eq(final_code(selected, report(failed=true)), selected)
  }
}

///|
test "the report line also goes to standard error unless the console writes errors there" {
  assert_true(reports_on_console(@sinks.SessionSettings::standard()))
  let stdout = @sinks.SessionSettings::new(
    console=@sinks.ConsoleSink::new(stream=StandardOutput),
  )
  assert_false(reports_on_console(stdout))
  let critical = @sinks.SessionSettings::new(
    console=@sinks.ConsoleSink::new(minimum=Critical),
  )
  assert_false(reports_on_console(critical))
  assert_false(reports_on_console(@sinks.SessionSettings::new()))
}

///|
/// A status that accepted `accepted` records, with a standard-error console
/// that failed or not.
fn status(accepted : Int64, failed~ : Bool) -> @sinks.SessionReport raise {
  let failure = if failed {
    Some(@sinks.SinkFailure::new(Write, Console(StandardError), "EPIPE"))
  } else {
    None
  }
  @sinks.SessionReport::new(
    accepted~,
    dropped=@sinks.DropCounts::new(
      queue_full=0L,
      oversized=0L,
      closed=0L,
      reentrant=0L,
    ),
    destinations=[
      @sinks.DestinationReport::new(
        Console(StandardError),
        written=accepted,
        undelivered=0L,
        failure?,
      ),
    ],
    drain_timed_out=false,
    closed=false,
  )
}

///|
async test "the report writer logs each default report line as an error" {
  let memory = @lander_logging.MemoryLogger::new()
  let calls = Ref(0)
  let writer = report_through(memory, @sinks.SessionSettings::standard(), () => {
    calls.val += 1
    // The second read sees the accepted event and a healthy console.
    status(if calls.val == 1 { 0L } else { 1L }, failed=false) catch {
      _ => abort("valid status")
    }
  })
  writer("acme: bad option")
  let events = memory.events()
  assert_eq(events.length(), 1)
  assert_eq(events[0].level, Error)
  assert_eq(events[0].message(), "acme: bad option")
  assert_eq(events[0].property("Failure"), Some(Json::string("acme: bad option")))
}

///|
test "a console that failed does not count as showing the report" {
  assert_true(console_healthy(status(1L, failed=false)))
  assert_false(console_healthy(status(1L, failed=true)))
  let stdout_only = @sinks.SessionReport::new(
    accepted=1L,
    dropped=@sinks.DropCounts::new(
      queue_full=0L,
      oversized=0L,
      closed=0L,
      reentrant=0L,
    ),
    destinations=[
      @sinks.DestinationReport::new(
        Console(StandardOutput),
        written=1L,
        undelivered=0L,
      ),
    ],
    drain_timed_out=false,
    closed=false,
  )
  assert_false(console_healthy(stdout_only))
}
