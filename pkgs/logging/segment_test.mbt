///|
/// The one event that `info` gives for `template` and `args`.
fn segment_event(template : String, args : Array[Json]) -> @logging.LogEvent {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info(template, args)
  memory.events()[0]
}

///|
/// The text of all segments of `event`, in order.
fn joined(event : @logging.LogEvent) -> String {
  event.segments().map(segment => segment.text()).join("")
}

///|
test "segments separate literal text from bound values" {
  let event = segment_event("Loaded {Count} files from {Path}", [3, "src"])
  assert_eq(event.segments(), [
    Text("Loaded "),
    Value(name="Count", value=3),
    Text(" files from "),
    Value(name="Path", value="src"),
  ])
  assert_eq(joined(event), "Loaded 3 files from src")
}

///|
test "the joined segments equal the message for the template corpus" {
  let corpus : Array[(String, Array[Json])] = [
    ("Disk {Name} is low", ["C"]),
    ("Loaded {Count} files from {Path}", [3, "src"]),
    ("{A}{B_2}", [1, 2]),
    ("Use {{Name}} for {Value}", [7]),
    ("Value {Name", [5]),
    ("Empty {} here", [1]),
    ("A {first name} B", ["x"]),
    ("Close } only", []),
    ("", []),
    ("From {Path} to {Target}", ["a"]),
    ("{Missing}", []),
    ("Done {Count}", [1, 2]),
    ("{Name} and {Name}", ["a", "b"]),
    ("{Name} and {Name} and {Other}", ["a", "b"]),
    ("Saved {Order}", [{ "id": 1 }]),
    ("{A} {B} {C} {D} {E}", ["text", true, Json::null(), [1, 2], 1.5]),
    ("{{{Name}}}", ["x"]),
    ("}}{{", []),
    ("{{{", []),
    ("Line {One}\nLine {Two}", ["a\nb", 2]),
    ("Unicode {Word} ✓", ["héllo 😀"]),
  ]
  for entry in corpus {
    let event = segment_event(entry.0, entry.1)
    assert_eq(joined(event), event.message())
  }
}

///|
test "a missing argument stays literal text next to other text" {
  let event = segment_event("From {Path} to {Target}", ["a"])
  assert_eq(event.segments(), [
    Text("From "),
    Value(name="Path", value="a"),
    Text(" to {Target}"),
  ])
}

///|
test "escaped and malformed braces are literal text" {
  assert_eq(segment_event("Use {{Name}} for {Value}", [7]).segments(), [
    Text("Use {Name} for "),
    Value(name="Value", value=7),
  ])
  assert_eq(segment_event("Value {Name", [5]).segments(), [Text("Value {Name")])
  assert_eq(segment_event("", []).segments(), [])
}

///|
test "a repeated name shows the first value in each hole" {
  let event = segment_event("{Name} and {Name}", ["a", "b"])
  assert_eq(event.segments(), [
    Value(name="Name", value="a"),
    Text(" and "),
    Value(name="Name", value="a"),
  ])
}

///|
test "a value keeps its JSON type and text renders as the message does" {
  let segments = segment_event("{A} {B} {C} {D} {E}", [
    "text",
    true,
    Json::null(),
    [1, 2],
    { "id": 1 },
  ]).segments()
  assert_true(segments[0] is Value(value=String("text"), ..))
  assert_true(segments[2] is Value(value=True, ..))
  assert_true(segments[4] is Value(value=Null, ..))
  assert_true(segments[6] is Value(value=Array(_), ..))
  assert_true(segments[8] is Value(value=Object(_), ..))
  inspect(segments.map(segment => segment.text()).join("|"), content=(
    #|text| |true| |null| |[1,2]| |{"id":1}
  ))
}

///|
test "a change to a read segment does not change the event" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("Saved {Order} and {Items}", [
    { "items": [1, 2] },
    [3],
  ])
  let event = memory.events()[0]
  let segments = event.segments()
  guard segments[1] is Value(value=Object(order), ..) else {
    fail("no order object")
  }
  order["items"] = Json::null()
  order["extra"] = true
  guard segments[3] is Value(value=Array(items), ..) else {
    fail("no items array")
  }
  items.push(4)
  segments.clear()
  let again = memory.events()[0]
  assert_eq(again.segments(), [
    Text("Saved "),
    Value(name="Order", value={ "items": [1, 2] }),
    Text(" and "),
    Value(name="Items", value=[3]),
  ])
  assert_eq(again.properties(), [("Order", { "items": [1, 2] }), ("Items", [3])])
  assert_eq(again.message(), "Saved {\"items\":[1,2]} and [3]")
}
