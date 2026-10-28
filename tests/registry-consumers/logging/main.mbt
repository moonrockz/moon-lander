///|
fn main raise {
  let memory = @library.MemoryLogger::new()
  (memory : &@library.Logger).info("Registry {Count}", [1])
  assert_eq(memory.events()[0].message(), "Registry 1")
  (memory : &@library.Logger).info("{path} {path} {array}", ["first", "last", [1, Json::null()]])
  let record = @formatting.LogRecord::capture(memory.events()[1], @formatting.LogTimestamp::earliest())
  let object = @formatting.format_json_object_line(record)
  guard @json.parse(object) is { "schemaVersion": 2, "properties": { "path": "last", "array": [1, Null], .. }, "duplicateProperties": { "path": ["first", "last"], .. }, .. } else { fail(object) }
  guard @json.parse(@formatting.format_json_line(record)) is { "schemaVersion": 1, "properties": Array(_), .. } else { fail("array schema changed") }
  println("ok")
}
