///|
/// The error text of the JSON examples.
let json_error : String =
  #|CompilerError: Unknown identifier calculate_total
  #|  at app.mbt:42

///|
suberror JsonSampleError {
  JsonSampleError(String)
}

///|
impl Show for JsonSampleError with output(self, logger) {
  let JsonSampleError(text) = self
  logger.write_string(text)
}

///|
/// The record of the one event that `write` gives at `millis` after
/// 2026-10-27T14:23:07.000Z.
fn json_sample(
  write : (&@logging.Logger) -> Unit,
  category? : String,
  millis? : Int64 = 0L,
) -> @formatting.LogRecord raise {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = match category {
    Some(name) => @logging.with_category(memory, name)
    None => memory
  }
  write(logger)
  let time = @formatting.LogTimestamp::from_epoch_millis(
    1793110987000L + millis,
  )
  @formatting.LogRecord::capture(memory.events()[0], time)
}

///|
test "JSON Lines output matches the examples byte for byte" {
  let info = json_sample(
    logger => logger.info("Loaded {Count} files from {Path}", [3, "src"]),
    category="workspace.loader",
    millis=24L,
  )
  inspect(@formatting.format_json_line(info), content=(
    #|{"schemaVersion":1,"timestamp":"2026-10-27T14:23:07.024Z","level":"Information","category":"workspace.loader","messageTemplate":"Loaded {Count} files from {Path}","message":"Loaded 3 files from src","properties":[{"name":"Count","value":3},{"name":"Path","value":"src"}],"error":null}
    #|
  ))
  let error = json_sample(
    logger => logger.error(
      "Compilation failed for {File}",
      ["app.mbt"],
      error=JsonSampleError(json_error),
    ),
    category="build.compiler",
    millis=41L,
  )
  inspect(@formatting.format_json_line(error), content=(
    #|{"schemaVersion":1,"timestamp":"2026-10-27T14:23:07.041Z","level":"Error","category":"build.compiler","messageTemplate":"Compilation failed for {File}","message":"Compilation failed for app.mbt","properties":[{"name":"File","value":"app.mbt"}],"error":"CompilerError: Unknown identifier calculate_total\n  at app.mbt:42"}
    #|
  ))
}

///|
test "a record without category or properties has null and an empty array" {
  let record = json_sample(logger => logger.debug("Plain", []))
  inspect(@formatting.format_json_line(record), content=(
    #|{"schemaVersion":1,"timestamp":"2026-10-27T14:23:07.000Z","level":"Debug","category":null,"messageTemplate":"Plain","message":"Plain","properties":[],"error":null}
    #|
  ))
}

///|
test "decoding the line recovers every value in order" {
  let record = json_sample(
    logger => logger.critical(
      "{Order} {Name} {Name} {Word}\n{Escape}",
      [
        { "id": 1, "lines": [{ "sku": "a", "qty": 2.5 }, Json::null()], "ok": true },
        "first",
        "second",
        "héllo ✓ 😀",
        "\u{1b}[31mred\r\n",
      ],
      error=JsonSampleError("line one\nline two\ttab \"quoted\" \\"),
    ),
    category="cat/egory",
  )
  let line = @formatting.format_json_line(record)
  // One physical line: the only LF is the last character, and there is no raw
  // ESC, CR or byte order mark.
  assert_eq(line.split("\n").to_array().length(), 2)
  assert_true(line.has_suffix("}\n"))
  assert_true(line.has_prefix("{\"schemaVersion\":1,"))
  assert_false(line.contains("\u{1b}"))
  assert_false(line.contains("\r"))
  assert_false(line.contains("\u{feff}"))
  assert_true(line.contains("\\u001b[31mred\\r\\n"))
  let decoded = @json.parse(line.trim_end(chars="\n").to_owned())
  guard decoded is Object(fields) else { fail("not an object") }
  assert_eq(fields.keys().to_array(), [
    "schemaVersion", "timestamp", "level", "category", "messageTemplate", "message",
    "properties", "error",
  ])
  assert_eq(fields.get("schemaVersion"), Some(1))
  assert_eq(fields.get("level"), Some("Critical"))
  assert_eq(fields.get("category"), Some("cat/egory"))
  assert_eq(fields.get("message"), Some(Json::string(record.message())))
  assert_eq(fields.get("messageTemplate"), Some(Json::string(record.template())))
  assert_eq(
    fields.get("error"),
    Some("line one\nline two\ttab \"quoted\" \\"),
  )
  assert_eq(fields.get("properties"), Some([
    {
      "name": "Order",
      "value": {
        "id": 1,
        "lines": [{ "sku": "a", "qty": 2.5 }, Json::null()],
        "ok": true,
      },
    },
    { "name": "Name", "value": "first" },
    { "name": "Name", "value": "second" },
    { "name": "Word", "value": "héllo ✓ 😀" },
    { "name": "Escape", "value": "\u{1b}[31mred\r\n" },
  ]))
}

///|
test "a number that is not finite is null and number text is kept" {
  let record = json_sample(logger => logger.info("{A} {B} {C} {D}", [
    Json::number(@double.not_a_number),
    Json::number(@double.infinity),
    Json::number(1.0, repr="1.00"),
    Json::number(2.0, repr="2\n\"x\""),
  ]))
  let line = @formatting.format_json_line(record)
  assert_true(
    line.contains(
      "[{\"name\":\"A\",\"value\":null},{\"name\":\"B\",\"value\":null},{\"name\":\"C\",\"value\":1.00},{\"name\":\"D\",\"value\":2}]",
    ),
  )
  ignore(@json.parse(line.trim_end(chars="\n").to_owned()))
}

///|
test "number text must have the complete JSON number grammar" {
  let kept = ["0", "-0", "12", "1.5", "0.25", "1e3", "1E+3", "-2.5e-7"]
  let rejected = ["1e", "+1", "01", "--2", "1.", ".5", "1e+", "-", "0x1", "1.2.3"]
  for text in kept + rejected {
    let record = json_sample(logger => logger.info("{N}", [
      Json::number(7.0, repr=text),
    ]))
    let line = @formatting.format_json_line(record)
    let expected = if kept.contains(text) { text } else { "7" }
    assert_true(
      line.contains("{\"name\":\"N\",\"value\":\{expected}}"),
      msg="\{text}: \{line}",
    )
    ignore(@json.parse(line.trim_end(chars="\n").to_owned()))
  }
}
