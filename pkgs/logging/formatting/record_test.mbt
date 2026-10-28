///|
/// An error whose `Show` text can change after the event.
suberror ChangingError {
  ChangingError(Ref[String])
}

///|
impl Show for ChangingError with output(self, logger) {
  let ChangingError(text) = self
  logger.write_string(text.val)
}

///|
test "capture keeps each part of the event and the error text of that time" {
  let text = Ref("before")
  let memory = @logging.MemoryLogger::new()
  @logging.with_category(memory, "app").warn(
    "Disk {Name} at {Percent}",
    ["C", 91],
    error=ChangingError(text),
  )
  let time = @formatting.LogTimestamp::from_epoch_millis(5L)
  let record = @formatting.LogRecord::capture(memory.events()[0], time)
  text.val = "after"
  assert_eq(record.timestamp(), time)
  assert_eq(record.level(), Warning)
  assert_eq(record.category(), Some("app"))
  assert_eq(record.template(), "Disk {Name} at {Percent}")
  assert_eq(record.message(), "Disk C at 91")
  assert_eq(record.properties(), [("Name", "C"), ("Percent", 91)])
  assert_eq(record.segments().length(), 4)
  assert_eq(record.error_text(), Some("before"))
}

///|
test "a record has no error text when the event has no error" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("Done", [])
  let record = @formatting.LogRecord::capture(
    memory.events()[0],
    @formatting.LogTimestamp::earliest(),
  )
  assert_eq(record.error_text(), None)
  assert_eq(record.category(), None)
}

///|
test "a change to read segments or properties does not change the record" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("Saved {Order}", [{ "items": [1, 2] }])
  let record = @formatting.LogRecord::capture(
    memory.events()[0],
    @formatting.LogTimestamp::earliest(),
  )
  guard record.segments()[1] is Value(value=Object(order), ..) else {
    fail("no order segment")
  }
  order["items"] = Json::null()
  guard record.properties()[0].1 is Object(again) else {
    fail("no order property")
  }
  again.clear()
  record.segments().clear()
  assert_eq(record.properties(), [("Order", { "items": [1, 2] })])
  assert_eq(record.segments()[1], Value(name="Order", value={ "items": [1, 2] }))
  inspect(@formatting.format_json_line(record), content=(
    #|{"schemaVersion":1,"timestamp":"1970-01-01T00:00:00.000Z","level":"Information","category":null,"messageTemplate":"Saved {Order}","message":"Saved {\"items\":[1,2]}","properties":[{"name":"Order","value":{"items":[1,2]}}],"error":null}
    #|
  ))
}

///|
test "the UTF-8 length counts bytes, not characters" {
  assert_eq(@formatting.utf8_length(""), 0L)
  assert_eq(@formatting.utf8_length("a"), 1L)
  assert_eq(@formatting.utf8_length("\u{7f}"), 1L)
  assert_eq(@formatting.utf8_length("\u{80}"), 2L)
  assert_eq(@formatting.utf8_length("é"), 2L)
  assert_eq(@formatting.utf8_length("\u{7ff}"), 2L)
  assert_eq(@formatting.utf8_length("\u{800}"), 3L)
  assert_eq(@formatting.utf8_length("✓"), 3L)
  assert_eq(@formatting.utf8_length("\u{ffff}"), 3L)
  assert_eq(@formatting.utf8_length("😀"), 4L)
  assert_eq(@formatting.utf8_length("a é ✓ 😀\n"), 14L)
}
