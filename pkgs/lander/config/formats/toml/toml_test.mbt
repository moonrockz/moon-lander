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
