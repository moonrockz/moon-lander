///|
/// 2026-10-27T14:23:07.024Z.
fn sample_time() -> @formatting.LogTimestamp {
  @formatting.LogTimestamp::from_epoch_millis(1793110987024L) catch {
    _ => abort("a valid sample time")
  }
}

///|
/// A test output: it keeps each payload, can wait before each write until it
/// is released, and can fail from a given write on.
priv struct Recorder {
  target : @sinks.SinkTarget
  written : Array[String]
  mut stalled : Bool
  released : @async.CondVar
  mut fail_from : Int
  mut writes : Int
  mut closes : Int
}

///|
fn Recorder::new(target : @sinks.SinkTarget) -> Recorder {
  {
    target,
    written: [],
    stalled: false,
    released: @async.CondVar::Cond(),
    fail_from: -1,
    writes: 0,
    closes: 0,
  }
}

///|
fn Recorder::release(self : Recorder) -> Unit {
  self.stalled = false
  self.released.broadcast()
}

///|
fn Recorder::sink(self : Recorder, minimum? : @logging.Level = Trace) -> Sink {
  Sink::new(self.target, minimum, record => "\{record.timestamp()} \{record.message()}\n", {
    write: async fn(text) {
      while self.stalled {
        self.released.wait()
        // A cancelled writer stops here, as a production adapter does.
        if @async.is_being_cancelled() {
          fail("cancelled")
        }
      }
      self.writes += 1
      if self.fail_from >= 0 && self.writes > self.fail_from {
        return Some(@sinks.SinkFailure::new(Write, self.target, "disk full"))
      }
      self.written.push(text)
      None
    },
    close: fn() {
      self.closes += 1
      []
    },
  })
}

///|
fn settings(
  event_limit? : Int = 1024,
  byte_limit? : Int64 = 8L * 1024L * 1024L,
  record_limit? : Int64 = 1024L * 1024L,
  drain_millis? : Int = 5000,
) -> @sinks.SessionSettings raise {
  @sinks.SessionSettings::new(
    event_limit=@sinks.QueueEventLimit::count(event_limit),
    byte_limit=@sinks.QueueByteLimit::bytes(byte_limit),
    record_limit=@sinks.RecordByteLimit::bytes(record_limit),
    drain_limit=@lander_core.TimeLimit::millis(drain_millis),
  )
}

///|
/// Run `body` with a session over `sinks`, a fixed clock and `observer`.
async fn[X] with_test_session(
  settings : @sinks.SessionSettings,
  sinks : Array[Sink],
  body : async (Session) -> X,
  observer? : (@sinks.SinkFailure) -> Unit,
) -> X {
  run_session(settings, (_, _, _) => sinks, sample_time, observer, body)
}

///|
fn info(logger : &@logging.Logger, template : String, args : Array[Json]) -> Unit {
  logger.info(template, args)
}

///|
async test "accepted events reach each destination in order with one captured time" {
  let console = Recorder::new(Console(StandardError))
  let file = Recorder::new(files_target())
  let report = with_test_session(settings(), [console.sink(), file.sink()], session => {
    let logger = session.logger()
    info(logger, "Loaded {Count} files", [3])
    info(logger, "Done", [])
    session.close()
  })
  let expected = [
    "2026-10-27T14:23:07.024Z Loaded 3 files\n", "2026-10-27T14:23:07.024Z Done\n",
  ]
  assert_eq(console.written, expected)
  assert_eq(file.written, expected)
  assert_eq(report.accepted(), 2L)
  assert_eq(report.destinations().map(d => d.written()), [2L, 2L])
  assert_false(report.delivery_failed())
  assert_eq(console.closes, 1)
}

///|
async test "each destination writes only the levels at or above its minimum" {
  let console = Recorder::new(Console(StandardError))
  let file = Recorder::new(files_target())
  ignore(
    with_test_session(
      settings(),
      [console.sink(minimum=Warning), file.sink(minimum=Debug)],
      session => {
        let logger : &@logging.Logger = session.logger()
        logger.trace("trace", [])
        logger.debug("debug", [])
        logger.warn("warn", [])
        assert_false(logger.enabled(Trace))
        assert_true(logger.enabled(Debug))
        session.close()
      },
    ),
  )
  assert_eq(console.written.length(), 1)
  assert_eq(file.written.length(), 2)
}

///|
async test "a stalled writer bounds the queue by count and keeps the order" {
  let output = Recorder::new(Console(StandardError))
  output.stalled = true
  let report = with_test_session(settings(event_limit=3), [output.sink()], session => {
    let logger = session.logger()
    for i in 0..<10 {
      info(logger, "event {N}", [Json(i)])
    }
    let status = session.status()
    assert_eq(status.accepted(), 3L)
    assert_eq(status.dropped().queue_full(), 7L)
    assert_true(logger.enabled(Information))
    output.release()
    session.close()
  })
  assert_eq(output.written.map(line => line.split(" ").last().unwrap().to_owned()), [
    "0\n", "1\n", "2\n",
  ])
  assert_eq(report.dropped().queue_full(), 7L)
  assert_eq(report.dropped().total(), 7L)
}

///|
async test "the byte limit counts every destination and the in-flight record" {
  let first = Recorder::new(Console(StandardError))
  let second = Recorder::new(files_target())
  first.stalled = true
  // Each payload is "2026-10-27T14:23:07.024Z abcd\n": 30 bytes, so one record
  // is 60 bytes for two destinations.
  let report = with_test_session(
    settings(byte_limit=150L, record_limit=150L),
    [first.sink(), second.sink()],
    session => {
      let logger = session.logger()
      for _ in 0..<5 {
        info(logger, "abcd", [])
      }
      // The writer took the first record, but it is still counted.
      @async.sleep(10)
      info(logger, "abcd", [])
      first.release()
      session.close()
    },
  )
  assert_eq(report.accepted(), 2L)
  assert_eq(report.dropped().queue_full(), 4L)
}

///|
async test "an oversized record is counted and does not evict earlier records" {
  let output = Recorder::new(Console(StandardError))
  let report = with_test_session(
    settings(record_limit=40L, byte_limit=1000L),
    [output.sink()],
    session => {
      let logger = session.logger()
      info(logger, "short", [])
      info(logger, "a message that is longer than the record limit", [])
      info(logger, "tail", [])
      session.close()
    },
  )
  assert_eq(report.dropped().oversized(), 1L)
  assert_eq(report.accepted(), 2L)
  assert_eq(output.written.length(), 2)
}

///|
async test "a failed destination stops, counts undelivered records, and the others continue" {
  let console = Recorder::new(Console(StandardError))
  let file = Recorder::new(files_target())
  file.fail_from = 1
  let observed = []
  let report = with_test_session(
    settings(),
    [console.sink(), file.sink()],
    session => {
      let logger = session.logger()
      for i in 0..<4 {
        info(logger, "event {N}", [Json(i)])
      }
      session.close()
    },
    observer=failure => observed.push(failure.operation()),
  )
  assert_eq(console.written.length(), 4)
  assert_eq(file.written.length(), 1)
  assert_eq(file.writes, 2)
  let destinations = report.destinations()
  assert_eq(destinations[1].written(), 1L)
  assert_eq(destinations[1].undelivered(), 3L)
  assert_true(destinations[1].failure() is Some(_))
  assert_true(report.delivery_failed())
  assert_eq(observed, [Write])
  assert_eq(
    report.failure_messages(),
    ["logging: write failed for files /logs/acme.log.lock: disk full"],
  )
}

///|
async test "a log call from the observer is dropped as reentrant" {
  let output = Recorder::new(Console(StandardError))
  output.fail_from = 0
  // A healthy second destination keeps the level enabled.
  let healthy = Recorder::new(files_target())
  let calls = []
  let logger_ref : Ref[SessionLogger?] = { val: None }
  let report = with_test_session(
    settings(),
    [output.sink(), healthy.sink()],
    session => {
      logger_ref.val = Some(session.logger())
      info(session.logger(), "first", [])
      // The observer runs while the session is open.
      ignore(session.drain())
      session.close()
    },
    observer=failure => {
      calls.push(failure.operation())
      if logger_ref.val is Some(logger) {
        info(logger, "from the observer", [])
      }
    },
  )
  assert_eq(calls, [Write])
  assert_eq(report.dropped().reentrant(), 1L)
  assert_eq(report.accepted(), 1L)
}

///|
suberror LoudError {
  Loud(SessionLogger)
}

///|
/// The text of the error logs through the session.
impl Show for LoudError with output(self, logger) {
  let Loud(session_logger) = self
  info(session_logger, "from show", [])
  logger.write_string("loud")
}

///|
async test "a log call from the Show of an error is dropped as reentrant" {
  let output = Recorder::new(Console(StandardError))
  let report = with_test_session(settings(), [output.sink()], session => {
    let logger : &@logging.Logger = session.logger()
    logger.error("failed", [], error=Loud(session.logger()))
    session.close()
  })
  assert_eq(report.dropped().reentrant(), 1L)
  assert_eq(report.accepted(), 1L)
}

///|
async test "close is idempotent and a late event is counted as closed" {
  let output = Recorder::new(Console(StandardError))
  let logger_ref : Ref[SessionLogger?] = { val: None }
  let (first, second) = with_test_session(settings(), [output.sink()], session => {
    logger_ref.val = Some(session.logger())
    info(session.logger(), "before", [])
    let first = session.close()
    let second = session.close()
    (first, second)
  })
  assert_eq(first, second)
  assert_eq(output.closes, 1)
  guard logger_ref.val is Some(logger) else { fail("no logger") }
  let as_trait : &@logging.Logger = logger
  assert_false(as_trait.enabled(Critical))
  logger.log(
    {
      let memory = @logging.MemoryLogger::new()
      (memory : &@logging.Logger).info("late", [])
      memory.events()[0]
    },
  )
  assert_eq(first.dropped().closed(), 0L)
  assert_eq(logger.core.snapshot().dropped().closed(), 1L)
}

///|
async test "drain waits for its barrier while producers continue" {
  let output = Recorder::new(Console(StandardError))
  let report = with_test_session(settings(), [output.sink()], session => {
    let logger = session.logger()
    for i in 0..<5 {
      info(logger, "early {N}", [Json(i)])
    }
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        for i in 0..<200 {
          info(logger, "late {N}", [Json(i)])
          @async.pause()
        }
      })
      assert_true(session.drain())
      assert_true(output.written.length() >= 5)
      assert_true(output.written[4].contains("early 4"))
    })
    session.close()
  })
  assert_eq(report.accepted(), 205L)
}

///|
async test "a drain timeout ends close and counts the records it did not write" {
  let output = Recorder::new(Console(StandardError))
  output.stalled = true
  let report = with_test_session(settings(drain_millis=50), [output.sink()], session => {
    let logger = session.logger()
    for _ in 0..<3 {
      info(logger, "stuck", [])
    }
    session.close()
  })
  assert_true(report.drain_timed_out())
  assert_true(report.delivery_failed())
  assert_eq(report.destinations()[0].undelivered(), 3L)
  assert_eq(output.closes, 1)
}

///|
async test "with_session closes the session when the body raises" {
  let output = Recorder::new(Console(StandardError))
  let result : Result[Unit, Error] = try {
    Ok(
      with_test_session(settings(), [output.sink()], session => {
        info(session.logger(), "before the failure", [])
        fail("body failed")
      }),
    )
  } catch {
    error => Err(error)
  }
  assert_true(result is Err(_))
  assert_eq(output.written.length(), 1)
  assert_eq(output.closes, 1)
}

///|
/// The target of the file set `acme` in `/logs`.
fn files_target() -> @sinks.SinkTarget {
  @sinks.FileSink::new(logs(), acme()).target()
}

///|
async test "a drain after a drain timeout returns false at once" {
  let output = Recorder::new(Console(StandardError))
  output.stalled = true
  let drained = with_test_session(settings(drain_millis=50), [output.sink()], session => {
    info(session.logger(), "stuck", [])
    ignore(session.close())
    @async.with_timeout_opt(1000, () => session.drain())
  })
  assert_eq(drained, Some(false))
}

///|
async test "a timeout at the second destination counts the front record once" {
  let first = Recorder::new(Console(StandardError))
  let second = Recorder::new(files_target())
  second.stalled = true
  let report = with_test_session(
    settings(drain_millis=50),
    [first.sink(), second.sink()],
    session => {
      let logger = session.logger()
      info(logger, "one", [])
      info(logger, "two", [])
      session.close()
    },
  )
  let destinations = report.destinations()
  assert_eq(destinations[0].written(), 1L)
  assert_eq(destinations[0].undelivered(), 1L)
  assert_eq(destinations[1].written(), 0L)
  assert_eq(destinations[1].undelivered(), 2L)
  // A cancelled writer reports no failure for a healthy destination.
  assert_eq(destinations[0].failure(), None)
  assert_eq(destinations[1].failure(), None)
  assert_eq(second.closes, 1)
}
