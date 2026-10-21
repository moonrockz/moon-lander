///|
fn names(value : @config.ConfigValue) -> Array[String] {
  guard value.to_ion().kind() is Struct(fields) else { return [] }
  fields.map(field => field.name().text().unwrap_or(""))
}

///|
test "TOML scalars, arrays and tables map to the value tree" {
  let text =
    #|title = "demo"
    #|count = 42
    #|large = 9223372036854775807
    #|ratio = 0.5
    #|enabled = true
    #|tags = ["a", "b"]
    #|
    #|[ir]
    #|layout = "tree"
  let value = @toml.parse(text, origin="app.toml")
  @expect.expect(value).to_equal(
    @config.fields([
      ("title", @config.string("demo")),
      ("count", @config.int(42)),
      ("large", @config.int(9223372036854775807)),
      ("ratio", @config.float(0.5)),
      ("enabled", @config.bool(true)),
      ("tags", @config.list([@config.string("a"), @config.string("b")])),
      ("ir", @config.fields([("layout", @config.string("tree"))])),
    ]),
  )
}

///|
test "TOML keeps the field order" {
  let value = @toml.parse("b = 1\na = 2\nc = 3\n", origin="app.toml")
  @expect.expect(names(value)).to_equal(["b", "a", "c"])
}

///|
test "Parse error with origin" {
  try @toml.parse("a = ", origin="/w/app.toml") catch {
    Parse(format~, origin~, line~, column~, ..) as error => {
      @expect.expect((format, origin, line, column)).to_equal(
        ("TOML", "/w/app.toml", None, None),
      )
      @expect.expect(error.message()).to_start_with(
        "Failed to parse TOML configuration /w/app.toml",
      )
    }
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected invalid TOML to raise")
  }
}

///|
test "the TOML format selects the toml extension" {
  let format = @toml.format()
  @expect.expect((format.name, format.extensions)).to_equal(("TOML", ["toml"]))
  @expect.expect((format.parse)("a = 1", "app.toml")).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "TOML date and time values" {
  for (text, expected) in [
    ("2026-09-28T12:30:00Z", "2026-09-28T12:30:00Z"),
    ("2026-09-28T12:30:00", "2026-09-28T12:30:00-00:00"),
    ("2026-09-28", "2026-09-28"),
    ("2026-09-28t12:30:00z", "2026-09-28T12:30:00Z"),
    ("2026-09-28 12:30:00", "2026-09-28T12:30:00-00:00"),
    ("2026-09-28T12:30:00.1234567890+05:30", "2026-09-28T12:30:00.1234567890+05:30"),
    ("2026-09-28T12:30:00.00100-07:00", "2026-09-28T12:30:00.00100-07:00"),
    ("2026-09-28T12:30:00.00100", "2026-09-28T12:30:00.00100-00:00"),
  ] {
    let value = @toml.parse("value = " + text, origin="app.toml")
    guard value.to_ion().kind() is Struct(fields) else { fail("expected a table") }
    guard fields[0].value().kind() is Timestamp(timestamp) else {
      fail("date lost its timestamp type")
    }
    @expect.expect(timestamp.to_ion_string()).to_equal(expected)
  }
}

///|
test "TOML local times keep their annotation and fractional spelling" {
  for spelling in ["12:30:00", "12:30:00.00100"] {
    let value = @toml.parse("value = " + spelling, origin="app.toml")
    guard value.to_ion().kind() is Struct(fields) else { fail("expected a table") }
    let time = fields[0].value()
    guard time.kind() is String(actual) else { fail("local time lost its string type") }
    @expect.expect(actual).to_equal(spelling)
    @expect.expect(time.annotations().map(token => token.text())).to_equal(
      [Some("toml_local_time")],
    )
  }
}

///|
test "TOML date and time mapping recurses through tables and arrays" {
  let value = @toml.parse(
    "[nested]\nvalues = [2026-09-28, 12:30:00]",
    origin="app.toml",
  )
  guard value.to_ion().kind() is Struct(root) else { fail("expected a table") }
  guard root[0].value().kind() is Struct(nested) else { fail("expected nested table") }
  guard nested[0].value().kind() is List(items) else { fail("expected a list") }
  guard items[0].kind() is Timestamp(day) else { fail("date lost its type") }
  @expect.expect(day.to_ion_string()).to_equal("2026-09-28")
  @expect.expect(items[1].kind() is String("12:30:00")).to_be_true()
  @expect.expect(items[1].annotations().map(token => token.text())).to_equal(
    [Some("toml_local_time")],
  )
}

///|
test "Large TOML integer stays exact across the Int64 range" {
  for spelling in [
    "9223372036854775807", "-9223372036854775808", "9007199254740993",
  ] {
    let value = @toml.parse("large = " + spelling, origin="app.toml")
    guard value.to_ion().kind() is Struct(fields) else { fail("expected a table") }
    guard fields[0].value().kind() is Int(integer) else { fail("integer lost its type") }
    @expect.expect(integer.to_string()).to_equal(spelling)
  }
}
