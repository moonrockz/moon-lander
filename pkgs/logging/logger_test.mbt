///|
/// An application logger that implements only `log`, so it uses the default
/// `enabled`.
struct AppLogger {
  received : Array[@logging.LogEvent]
}

///|
impl @logging.Logger for AppLogger with log(self, event) {
  self.received.push(event)
}

///|
/// An application logger that enables only `Warning` and higher, and counts the
/// calls to its `log`.
struct CountingLogger {
  mut calls : Int
}

///|
impl @logging.Logger for CountingLogger with enabled(_self, level) {
  level >= Warning
}

///|
impl @logging.Logger for CountingLogger with log(self, _event) {
  self.calls += 1
}

///|
suberror LoadFailed {
  LoadFailed(String)
}

///|
fn write_each_level(logger : &@logging.Logger) -> Unit {
  logger.trace("t", [])
  logger.debug("d", [])
  logger.info("i", [])
  logger.warn("w", [])
  logger.error("e", [])
  logger.critical("c", [])
}

///|
test "an application logger with only log gets an event at each level" {
  let app = AppLogger::{ received: [] }
  write_each_level(app)
  assert_eq(app.received.map(event => event.level), [
    Trace, Debug, Information, Warning, Error, Critical,
  ])
  assert_eq(app.received.map(event => event.template), [
    "t", "d", "i", "w", "e", "c",
  ])
}

///|
test "warn writes a warning event with the template" {
  let app = AppLogger::{ received: [] }
  (app : &@logging.Logger).warn("Disk is low", [])
  assert_eq(app.received.length(), 1)
  let event = app.received[0]
  assert_eq(event.level, Warning)
  assert_eq(event.template, "Disk is low")
  assert_eq(event.category, None)
  assert_true(event.error is None)
}

///|
test "error keeps the error value" {
  let app = AppLogger::{ received: [] }
  (app : &@logging.Logger).error(
    "Load failed",
    [],
    error=LoadFailed("config.toml"),
  )
  let event = app.received[0]
  assert_eq(event.level, Error)
  assert_eq(event.properties, [])
  match event.error {
    Some(LoadFailed(path)) => assert_eq(path, "config.toml")
    _ => fail("the event does not hold the error")
  }
}

///|
test "a disabled level builds no event" {
  let counting = CountingLogger::{ calls: 0 }
  let logger : &@logging.Logger = counting
  logger.debug("Not written", [])
  assert_eq(counting.calls, 0)
  logger.error("Written", [])
  assert_eq(counting.calls, 1)
}

///|
/// A library function that takes a logger and does not know its backend.
fn load_files(logger : &@logging.Logger) -> Unit {
  logger.info("Loaded files", [])
}

///|
test "library code gives the same event to each backend" {
  let app = AppLogger::{ received: [] }
  let memory = @logging.MemoryLogger::new()
  load_files(app)
  load_files(memory)
  let from_app = app.received[0]
  let from_memory = memory.events()[0]
  assert_eq(from_app.level, from_memory.level)
  assert_eq(from_app.template, from_memory.template)
  assert_eq(from_app.properties, from_memory.properties)
  assert_eq(from_app.category, from_memory.category)
}
