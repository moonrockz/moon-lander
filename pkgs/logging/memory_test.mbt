///|
test "the in-memory logger keeps events in write order" {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = memory
  logger.info("first", [])
  logger.warn("second", [])
  let events = memory.events()
  assert_eq(events.map(event => event.level), [Information, Warning])
  assert_eq(events.map(event => event.template), ["first", "second"])
}

///|
test "events gives a copy" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("one", [])
  let events = memory.events()
  events.clear()
  assert_eq(memory.events().length(), 1)
}
