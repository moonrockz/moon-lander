///|
fn first_event(
  write : (&@logging.Logger) -> Unit,
  category? : String,
) -> @logging.LogEvent {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = match category {
    Some(name) => @logging.with_category(memory, name)
    None => memory
  }
  write(logger)
  memory.events()[0]
}

///|
suberror NotFound {
  NotFound
}

///|
impl Show for NotFound with output(_self, logger) {
  logger.write_string("NotFound")
}

///|
/// An error that holds a token and shows only that a token exists.
suberror TokenRejected {
  TokenRejected(token~ : String)
}

///|
impl Show for TokenRejected with output(_self, logger) {
  logger.write_string("TokenRejected(token=<redacted>)")
}

///|
test "a line with a category" {
  let event = first_event(
    logger => logger.info("Loaded {Count} files from {Path}", [3, "src"]),
    category="morphir.build",
  )
  assert_eq(event.to_line(), "[INF] morphir.build: Loaded 3 files from src")
}

///|
test "a line without a category" {
  let event = first_event(logger => logger.warn("Disk {Name} is low", ["C"]))
  assert_eq(event.to_line(), "[WRN] Disk C is low")
}

///|
test "a line with an error" {
  let event = first_event(logger => logger.error(
    "Load failed",
    [],
    error=NotFound,
  ))
  assert_eq(event.to_line(), "[ERR] Load failed\n  error: NotFound")
}

///|
test "the six level codes" {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = memory
  logger.trace("x", [])
  logger.debug("x", [])
  logger.info("x", [])
  logger.warn("x", [])
  logger.error("x", [])
  logger.critical("x", [])
  assert_eq(memory.events().map(event => event.to_line()), [
    "[TRC] x", "[DBG] x", "[INF] x", "[WRN] x", "[ERR] x", "[CRT] x",
  ])
}

///|
test "the error line uses the Show text of the error" {
  let event = first_event(logger => logger.error(
    "Sign-in failed",
    [],
    error=TokenRejected(token="s3cr3t"),
  ))
  let line = event.to_line()
  assert_eq(
    line, "[ERR] Sign-in failed\n  error: TokenRejected(token=<redacted>)",
  )
  assert_false(line.contains("s3cr3t"))
}
