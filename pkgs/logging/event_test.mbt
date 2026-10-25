///|
fn kept_event(
  template : String,
  args : Array[Json],
) -> (@logging.MemoryLogger, @logging.LogEvent) {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info(template, args)
  (memory, memory.events()[0])
}

///|
test "a change to the read properties does not change the event" {
  let (memory, event) = kept_event("Loaded {Count}", [3])
  event.properties().clear()
  assert_eq(memory.events()[0].properties(), [("Count", 3)])
  assert_eq(memory.events()[0].message(), "Loaded 3")
}

///|
test "a change to a nested value does not change the event" {
  let (memory, event) = kept_event("Saved {Order}", [{ "items": [1, 2] }])
  guard event.property("Order") is Some(Object(order)) else {
    fail("no order object")
  }
  order["items"] = Json::null()
  guard event.properties()[0].1 is Object(again) else { fail("no order object") }
  again.clear()
  assert_eq(memory.events()[0].property("Order"), Some({ "items": [1, 2] }))
}

///|
test "a change to an argument after the call does not change the event" {
  let items : Array[Json] = [1, 2]
  let (memory, _) = kept_event("Saved {Items}", [Json::array(items)])
  items.push(3)
  assert_eq(memory.events()[0].message(), "Saved [1,2]")
}

///|
test "two backends of a fan-out cannot change the event of each other" {
  let first = @logging.MemoryLogger::new()
  let second = @logging.MemoryLogger::new()
  @logging.fan_out([first, second]).info("Loaded {Count}", [3])
  first.events()[0].properties().clear()
  assert_eq(second.events()[0].properties(), [("Count", 3)])
}
