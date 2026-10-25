///|
/// The one event that `write` gives for `template` and `args`.
fn event_of(template : String, args : Array[Json]) -> @logging.LogEvent {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info(template, args)
  memory.events()[0]
}

///|
test "two holes bind in order" {
  let event = event_of("Loaded {Count} files from {Path}", [3, "src"])
  assert_eq(event.properties, [("Count", 3), ("Path", "src")])
  assert_eq(event.message(), "Loaded 3 files from src")
}

///|
test "warning method binds its argument" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).warn("Disk {Name} is low", ["C"])
  let event = memory.events()[0]
  assert_eq(event.level, Warning)
  assert_eq(event.template, "Disk {Name} is low")
  assert_eq(event.property("Name"), Some("C"))
}

///|
test "escaped braces are not holes" {
  let event = event_of("Use {{Name}} for {Value}", [7])
  assert_eq(event.properties, [("Value", 7)])
  assert_eq(event.message(), "Use {Name} for 7")
}

///|
test "a missing argument keeps the hole text" {
  let event = event_of("From {Path} to {Target}", ["a"])
  assert_eq(event.properties, [("Path", "a")])
  assert_eq(event.message(), "From a to {Target}")
}

///|
test "an extra argument is dropped" {
  let event = event_of("Done {Count}", [1, 2])
  assert_eq(event.properties, [("Count", 1)])
  assert_eq(event.message(), "Done 1")
}

///|
test "an unclosed brace is literal text" {
  let event = event_of("Value {Name", [5])
  assert_eq(event.properties, [])
  assert_eq(event.message(), "Value {Name")
}

///|
test "one name twice keeps both pairs and shows the first value" {
  let event = event_of("{Name} and {Name}", ["a", "b"])
  assert_eq(event.properties, [("Name", "a"), ("Name", "b")])
  assert_eq(event.message(), "a and a")
}

///|
test "a number stays a number" {
  let event = event_of("Loaded {Count} files", [3])
  assert_eq(event.property("Count"), Some(Json::number(3)))
  assert_true(event.property("Count") is Some(Number(_, ..)))
}

///|
struct Order {
  id : Int
  total : Double
} derive(ToJson)

///|
test "a derived ToJson value stays an object" {
  let order = { id: 1, total: 9.5 }
  let event = event_of("Saved {Order}", [Json(order)])
  assert_eq(event.property("Order"), Some({ "id": 1, "total": 9.5 }))
}

///|
test "an object value renders as compact JSON" {
  let event = event_of("Saved {Order}", [{ "id": 1 }])
  assert_eq(event.message(), "Saved {\"id\":1}")
}

///|
test "other values render as JSON and text has no quotes" {
  let event = event_of("{A} {B} {C} {D} {E}", [
    "text",
    true,
    Json::null(),
    [1, 2],
    1.5,
  ])
  assert_eq(event.message(), "text true null [1,2] 1.5")
}
