///|
/// The error of `make`, or `None` when it succeeds.
fn[T] attempt(make : () -> T raise @sinks.SettingsError) -> @sinks.SettingsError? {
  try {
    ignore(make())
    None
  } catch {
    error => Some(error)
  }
}

///|
test "queue event limit accepts 1 and more, and rejects 0 and less" {
  assert_eq(@sinks.QueueEventLimit::count(1).to_int(), 1)
  assert_eq(@sinks.QueueEventLimit::default().to_int(), 1024)
  for count in [0, -1] {
    let result = attempt(() => @sinks.QueueEventLimit::count(count))
    guard result is Some(InvalidQueueEventLimit(count=found)) else {
      fail("accepted \{count}")
    }
    assert_eq(found, count)
  }
  inspect(
    attempt(() => @sinks.QueueEventLimit::count(0)).unwrap().message(),
    content="Invalid queue event limit 0: it must be 1 or more",
  )
}

///|
test "queue and record byte limits accept 1 and more, and reject 0 and less" {
  assert_eq(@sinks.QueueByteLimit::bytes(1L).to_int64(), 1L)
  assert_eq(@sinks.RecordByteLimit::bytes(1L).to_int64(), 1L)
  assert_eq(@sinks.QueueByteLimit::default().to_int64(), 8388608L)
  assert_eq(@sinks.RecordByteLimit::default().to_int64(), 1048576L)
  for bytes in [0L, -1L] {
    assert_true(
      attempt(() => @sinks.QueueByteLimit::bytes(bytes)) is Some(InvalidQueueByteLimit(..)),
    )
    assert_true(
      attempt(() => @sinks.RecordByteLimit::bytes(bytes)) is Some(InvalidRecordByteLimit(..)),
    )
  }
}

///|
test "a record limit equal to the queue limit is accepted and one byte more is rejected" {
  let queue = @sinks.QueueByteLimit::bytes(100L)
  let settings = @sinks.SessionSettings::new(
    byte_limit=queue,
    record_limit=@sinks.RecordByteLimit::bytes(100L),
  )
  assert_eq(settings.record_limit().to_int64(), 100L)
  let result = attempt(() => @sinks.SessionSettings::new(
    byte_limit=queue,
    record_limit=@sinks.RecordByteLimit::bytes(101L),
  ))
  guard result is Some(RecordLimitAboveQueueLimit(record=101L, queue=100L)) else {
    fail("accepted a record limit above the queue limit")
  }
}

///|
test "a log directory consumes an absolute path and rejects a NUL character" {
  let path = @lander_core.AbsolutePath::parse("/var/log/acme")
  let directory = @sinks.LogDirectory::from_absolute(path)
  assert_eq(directory.path(), path)
  let set = @rolling.FileSet::new(
    @rolling.LogFileStem::parse("acme"),
    Text,
    Size(@rolling.FileByteLimit::default()),
  )
  let first = set.parse_name("acme.log").unwrap()
  assert_eq(directory.file(first), "/var/log/acme/acme.log")
  assert_eq(directory.marker(set), "/var/log/acme/acme.log.lock")
  assert_eq(
    @sinks.LogDirectory::from_absolute(@lander_core.AbsolutePath::parse("/"))
    .file(first),
    "/acme.log",
  )
  let windows = @sinks.LogDirectory::from_absolute(
    @lander_core.AbsolutePath::parse("C:\\logs"),
  )
  assert_eq(windows.file(first), "C:/logs/acme.log")
  let path = @lander_core.AbsolutePath::parse("/var/log\u{0}x")
  let result = attempt(() => @sinks.LogDirectory::from_absolute(path))
  guard result is Some(InvalidLogDirectory(rule=NulCharacter, ..) as error) else {
    fail("accepted a NUL character")
  }
  inspect(
    error.message(),
    content="Invalid log directory \"/var/log\\u{00}x\": the path has a NUL character",
  )
}

///|
test "two file destinations cannot share a file set, but the formats can share a directory" {
  let directory = @sinks.LogDirectory::from_absolute(
    @lander_core.AbsolutePath::parse("/logs"),
  )
  let stem = @rolling.LogFileStem::parse("acme")
  let text = @sinks.FileSink::new(directory, stem)
  let json = @sinks.FileSink::new(directory, stem, format=JsonLines)
  let settings = @sinks.SessionSettings::new(files=[text, json])
  assert_eq(settings.files().length(), 2)
  let daily = @sinks.FileSink::new(directory, stem, policy=Daily)
  let result = attempt(() => @sinks.SessionSettings::new(files=[text, daily]))
  guard result is Some(DuplicateFileSet(name="acme.log.lock", ..)) else {
    fail("accepted two writers of one file set")
  }
}

///|
test "the standard settings write Information to standard error with Literate Auto colors" {
  let settings = @sinks.SessionSettings::standard()
  guard settings.console() is Some(console) else { fail("no console") }
  assert_eq(console.stream(), StandardError)
  assert_eq(console.minimum(), Information)
  assert_eq(console.color(), Auto)
  assert_eq(console.theme(), Literate)
  assert_eq(settings.files().length(), 0)
  assert_eq(settings.drain_limit().to_millis(), 5000)
  assert_eq(settings.event_limit(), @sinks.QueueEventLimit::default())
}

///|
test "the file defaults are text, daily and 10 MiB, and the newest 31 files" {
  let file = @sinks.FileSink::new(
    @sinks.LogDirectory::from_absolute(@lander_core.AbsolutePath::parse("/logs")),
    @rolling.LogFileStem::parse("acme"),
  )
  assert_eq(file.files().format(), Text)
  assert_eq(file.files().policy(), DailyAndSize(@rolling.FileByteLimit::default()))
  assert_eq(@rolling.FileByteLimit::default().to_int64(), 10485760L)
  assert_eq(file.retention(), @rolling.Retention::default())
  assert_eq(file.minimum(), Information)
  assert_eq(file.marker_path(), "/logs/acme.log.lock")
}

///|
test "Auto colors need a color terminal, no NO_COLOR and a terminal that is not dumb" {
  let none = @sinks.ColorHints::none()
  assert_true(@sinks.ColorMode::Auto.styles(ColorTerminal, none))
  for capability in [@sinks.TerminalCapability::PlainTerminal, Redirected, Unknown] {
    assert_false(@sinks.ColorMode::Auto.styles(capability, none))
    assert_true(@sinks.ColorMode::Always.styles(capability, none))
  }
  let no_color = @sinks.ColorHints::from_env(no_color=Some("1"), term=None)
  let empty = @sinks.ColorHints::from_env(no_color=Some(""), term=None)
  let dumb = @sinks.ColorHints::from_env(no_color=None, term=Some("dumb"))
  assert_false(@sinks.ColorMode::Auto.styles(ColorTerminal, no_color))
  assert_true(@sinks.ColorMode::Auto.styles(ColorTerminal, empty))
  assert_false(@sinks.ColorMode::Auto.styles(ColorTerminal, dumb))
  assert_true(@sinks.ColorMode::Always.styles(ColorTerminal, no_color))
  assert_false(@sinks.ColorMode::Never.styles(ColorTerminal, none))
}

///|
test "a console renders Literate only when its color mode permits styles" {
  let auto = @sinks.ConsoleSink::new()
  let none = @sinks.ColorHints::none()
  assert_eq(auto.render_theme(ColorTerminal, none), Literate)
  assert_eq(auto.render_theme(Redirected, none), Plain)
  assert_eq(auto.render_theme(Unknown, none), Plain)
  let forced = @sinks.ConsoleSink::new(stream=StandardOutput, color=Always)
  assert_eq(forced.render_theme(Unknown, none), Literate)
  assert_eq(forced.stream(), StandardOutput)
  let plain = @sinks.ConsoleSink::new(color=Never)
  assert_eq(plain.render_theme(ColorTerminal, none), Plain)
}

///|
test "reports count drops and delivery failures, and name each failure" {
  let failure = @sinks.SinkFailure::new(
    Write,
    files_target(),
    subject="acme-20261027.log",
    "disk full",
  )
  inspect(
    failure.message(),
    content="logging: write failed for files /logs/acme.log.lock (acme-20261027.log): disk full",
  )
  let retention = @sinks.SinkFailure::new(
    DeleteOldFile,
    files_target(),
    "busy",
  )
  let clean = @sinks.SessionReport::new(
    accepted=3L,
    dropped=@sinks.DropCounts::new(
      queue_full=1L,
      oversized=2L,
      closed=3L,
      reentrant=4L,
    ),
    destinations=[
      @sinks.DestinationReport::new(
        Console(StandardError),
        written=3L,
        undelivered=0L,
        retention_failure=retention,
      ),
    ],
    drain_timed_out=false,
    closed=true,
  )
  assert_eq(clean.dropped().total(), 10L)
  assert_false(clean.delivery_failed())
  assert_eq(clean.failure_messages(), [
    "logging: delete old file failed for files /logs/acme.log.lock: busy",
  ])
  let failed = @sinks.SessionReport::new(
    accepted=3L,
    dropped=clean.dropped(),
    destinations=[
      @sinks.DestinationReport::new(
        files_target(),
        written=1L,
        undelivered=2L,
        failure~,
      ),
    ],
    drain_timed_out=true,
    closed=true,
  )
  assert_true(failed.delivery_failed())
  assert_eq(failed.failure_messages().length(), 2)
  let undelivered = @sinks.SessionReport::new(
    accepted=1L,
    dropped=clean.dropped(),
    destinations=[
      @sinks.DestinationReport::new(
        Console(StandardOutput),
        written=0L,
        undelivered=1L,
      ),
    ],
    drain_timed_out=false,
    closed=true,
  )
  assert_true(undelivered.delivery_failed())
}

///|
test "a report keeps a copy of its destinations" {
  let destinations = [
    @sinks.DestinationReport::new(
      Console(StandardError),
      written=1L,
      undelivered=0L,
    ),
  ]
  let report = @sinks.SessionReport::new(
    accepted=1L,
    dropped=@sinks.DropCounts::new(
      queue_full=0L,
      oversized=0L,
      closed=0L,
      reentrant=0L,
    ),
    destinations~,
    drain_timed_out=false,
    closed=false,
  )
  destinations.clear()
  let read = report.destinations()
  read.clear()
  assert_eq(report.destinations().length(), 1)
}

///|
/// The target of the file set `acme` in `/logs`.
fn files_target() -> @sinks.SinkTarget raise {
  @sinks.FileSink::new(
    @sinks.LogDirectory::from_absolute(@lander_core.AbsolutePath::parse("/logs")),
    @rolling.LogFileStem::parse("acme"),
  ).target()
}

///|
test "JSON policies share file ownership and default to the ordered array" {
  let directory = @sinks.LogDirectory::from_absolute(@lander_core.AbsolutePath::parse("/logs"))
  let stem = @rolling.LogFileStem::parse("diagnostics")
  let legacy = @sinks.FileSink::new(directory, stem, format=JsonLines)
  let named = @sinks.FileSink::new(directory, stem, format=JsonLines, json_properties=NamedObject)
  assert_true(legacy.json_properties() is OrderedArray)
  assert_true(named.json_properties() is NamedObject)
  assert_eq(legacy.marker_path(), named.marker_path())
  let duplicate : @sinks.SettingsError? = try {
    ignore(@sinks.SessionSettings::new(files=[legacy, named]))
    None
  } catch { error => Some(error) }
  assert_true(duplicate is Some(DuplicateFileSet(..)))
}

///|
test "report constructors reject negative counts and a timeout of an open session" {
  for count in [-1L] {
    let result : @sinks.ReportError? = try {
      ignore(
        @sinks.DropCounts::new(
          queue_full=count,
          oversized=0L,
          closed=0L,
          reentrant=0L,
        ),
      )
      None
    } catch {
      error => Some(error)
    }
    guard result is Some(NegativeCount(count=-1L) as error) else {
      fail("accepted a negative count")
    }
    inspect(error.message(), content="Invalid count -1: it must be 0 or more")
  }
  assert_eq(
    @sinks.DestinationReport::new(Console(StandardError), written=0L, undelivered=0L).written(),
    0L,
  )
  let zero = @sinks.DropCounts::new(
    queue_full=0L,
    oversized=0L,
    closed=0L,
    reentrant=0L,
  )
  let open_timeout : @sinks.ReportError? = try {
    ignore(
      @sinks.SessionReport::new(
        accepted=0L,
        dropped=zero,
        destinations=[],
        drain_timed_out=true,
        closed=false,
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  assert_true(open_timeout is Some(TimeoutBeforeClose))
  let undelivered : @sinks.ReportError? = try {
    ignore(
      @sinks.DestinationReport::new(
        Console(StandardError),
        written=0L,
        undelivered=-1L,
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  assert_true(undelivered is Some(NegativeCount(count=-1L)))
}
