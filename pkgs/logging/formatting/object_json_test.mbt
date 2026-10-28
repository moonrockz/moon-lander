///|
test "object properties retain last values and complete interleaved histories" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info(
    "{path} {level} {path} {onlyArray} {path} {level} {duplicateProperties}",
    ["first", "event", Json::null(), [1, Json::null()], { "nested": [true, 2] }, false, "inside"],
  )
  let record = @formatting.LogRecord::capture(memory.events()[0], @formatting.LogTimestamp::earliest())
  let line = @formatting.format_json_object_line(record)
  guard @json.parse(line) is Object(fields) else { fail("not an object") }
  assert_eq(fields.get("schemaVersion"), Some(2))
  assert_eq(fields.get("level"), Some("Information"))
  assert_eq(fields.get("properties"), Some({
    "path": { "nested": [true, 2] },
    "level": false,
    "onlyArray": [1, Json::null()],
    "duplicateProperties": "inside",
  }))
  assert_eq(fields.get("duplicateProperties"), Some({
    "path": ["first", Json::null(), { "nested": [true, 2] }],
    "level": ["event", false],
  }))
  // The original record and schema version 1 stay ordered and unchanged.
  guard @json.parse(@formatting.format_json_line(record)) is { "schemaVersion": 1, "properties": Array(entries), .. } else { fail("array default changed") }
  assert_eq(entries.length(), 7)
}

///|
test "unique array and empty object properties omit duplicate history" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("{array} {object} {null}", [[1, 2], {}, Json::null()])
  (memory : &@logging.Logger).info("empty", [])
  for index, expected in [({ "array": [1, 2], "object": {}, "null": Json::null() } : Json), {}] {
    let record = @formatting.LogRecord::capture(memory.events()[index], @formatting.LogTimestamp::earliest())
    guard @json.parse(@formatting.format_json_object_line(record)) is Object(fields) else { fail("not an object") }
    assert_eq(fields.get("properties"), Some(expected))
    assert_eq(fields.get("duplicateProperties"), None)
  }
}

///|
test "a null last value wins and strings remain one physical JSON line" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("{value} {value} {text}", [1, Json::null(), "é 😀\n\r\u{1b}\"\\"])
  let record = @formatting.LogRecord::capture(memory.events()[0], @formatting.LogTimestamp::earliest())
  let line = @formatting.format_json_object_line(record)
  assert_eq(line.split("\n").count(), 2)
  assert_false(line.contains("\r"))
  assert_false(line.contains("\u{1b}"))
  guard @json.parse(line) is { "properties": { "value": Null, "text": "é 😀\n\r\u{1b}\"\\", .. }, "duplicateProperties": { "value": [1, Null], .. }, .. } else { fail(line) }
}
