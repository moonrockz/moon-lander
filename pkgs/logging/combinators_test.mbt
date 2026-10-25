///|
fn write_six(logger : &@logging.Logger) -> Unit {
  logger.trace("t", [])
  logger.debug("d", [])
  logger.info("i", [])
  logger.warn("w", [])
  logger.error("e", [])
  logger.critical("c", [])
}

///|
fn levels_of(memory : @logging.MemoryLogger) -> Array[@logging.Level] {
  memory.events().map(event => event.level)
}

///|
/// An application logger that enables only `Error` and higher.
struct ErrorsOnly {
  received : Array[@logging.LogEvent]
}

///|
impl @logging.Logger for ErrorsOnly with enabled(_self, level) {
  level >= Error
}

///|
impl @logging.Logger for ErrorsOnly with log(self, event) {
  self.received.push(event)
}

///|
test "the null logger enables no level and drops events" {
  let logger = @logging.null_logger()
  for
    level in [
      @logging.Level::Trace,
      Debug,
      Information,
      Warning,
      Error,
      Critical,
    ] {
    assert_false(logger.enabled(level))
  }
  logger.critical("Dropped", [])
}

///|
test "min_level drops the lower levels" {
  let memory = @logging.MemoryLogger::new()
  write_six(@logging.min_level(memory, Warning))
  assert_eq(levels_of(memory), [Warning, Error, Critical])
}

///|
test "min_level keeps the filter of the wrapped logger" {
  let app = ErrorsOnly::{ received: [] }
  let logger = @logging.min_level(app, Debug)
  assert_false(logger.enabled(Warning))
  logger.warn("Not passed", [])
  assert_eq(app.received.length(), 0)
}

///|
test "fan_out gives one event to two loggers" {
  let first = @logging.MemoryLogger::new()
  let second = @logging.MemoryLogger::new()
  @logging.fan_out([first, second]).info("Both", [])
  assert_eq(levels_of(first), [Information])
  assert_eq(levels_of(second), [Information])
}

///|
test "fan_out keeps the level of each logger" {
  let first = @logging.MemoryLogger::new()
  let second = @logging.MemoryLogger::new()
  let logger = @logging.fan_out([first, @logging.min_level(second, Error)])
  logger.warn("Only first", [])
  assert_eq(levels_of(first), [Warning])
  assert_eq(levels_of(second), [])
  assert_true(logger.enabled(Warning))
  assert_false(@logging.fan_out([@logging.null_logger()]).enabled(Critical))
}

///|
test "fan_out does not see later changes to its array" {
  let memory = @logging.MemoryLogger::new()
  let loggers : Array[&@logging.Logger] = [memory]
  let logger = @logging.fan_out(loggers)
  loggers.clear()
  logger.info("Still sent", [])
  assert_eq(levels_of(memory), [Information])
}

///|
test "with_category sets the category and keeps the other fields" {
  let memory = @logging.MemoryLogger::new()
  @logging.with_category(memory, "morphir.build").info("Loaded {Count} files", [
    3,
  ])
  let event = memory.events()[0]
  assert_eq(event.category, Some("morphir.build"))
  assert_eq(event.level, Information)
  assert_eq(event.template, "Loaded {Count} files")
  assert_eq(event.properties(), [("Count", 3)])
}

///|
test "a direct log call obeys the filter of a combinator" {
  let memory = @logging.MemoryLogger::new()
  let event = memory_event(Debug)
  @logging.min_level(memory, Warning).log(event)
  @logging.with_category(@logging.min_level(memory, Warning), "x").log(event)
  @logging.fan_out([@logging.min_level(memory, Warning)]).log(event)
  assert_eq(memory.events().length(), 0)
}

///|
/// One event at `level`, made through the level methods, because only this package
/// can build an event.
fn memory_event(level : @logging.Level) -> @logging.LogEvent {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).write(level, "event", [])
  memory.events()[0]
}

///|
test "the chain compiles with a MemoryLogger first" {
  let memory = @logging.MemoryLogger::new()
  let logger = memory
    |> @logging.min_level(Information)
    |> @logging.with_category("morphir.build")
  logger.debug("Dropped", [])
  logger.info("Kept", [])
  assert_eq(memory.events().map(event => event.category), [
    Some("morphir.build"),
  ])
}
