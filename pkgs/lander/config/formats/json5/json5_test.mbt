///|
fn expect_error(
  run : () -> @config.ConfigValue raise @config.ConfigError,
) -> @config.ConfigError {
  try run() catch {
    error => error
  } noraise {
    _ => abort("expected a configuration error")
  }
}

///|
test "JSON with comments" {
  let text =
    #|{ // comment
    #|  "ir": {"layout": "tree"}
    #|}
  let value = @json5.parse(text, origin="app.json")
  @expect.expect(value).to_equal(
    @config.fields([
      ("ir", @config.fields([("layout", @config.string("tree"))])),
    ]),
  )
}

///|
test "JSON number types" {
  let value = @json5.parse(
    "{\"a\": 3, \"b\": 1.5, \"c\": 1e3}",
    origin="app.json",
  )
  @expect.expect(value).to_equal(
    @config.fields([
      ("a", @config.int(3)),
      ("b", @config.float(1.5)),
      ("c", @config.int(1000)),
    ]),
  )
}

///|
test "JSON syntax error has a position" {
  let text =
    #|{
    #|    !
    #|}
  try @json5.parse(text, origin="app.json") catch {
    Parse(format~, origin~, line~, column~, ..) as error => {
      @expect.expect((format, origin, line, column)).to_equal(
        ("JSON5", "app.json", Some(2), Some(4)),
      )
      @expect.expect(error.message()).to_start_with(
        "Failed to parse JSON5 configuration app.json at line 2, column 4",
      )
    }
    _ => fail("expected a parse error")
  } noraise {
    _ => fail("expected invalid JSON to raise")
  }
}

///|
test "the JSON5 format selects json and json5 extensions" {
  let format = @json5.format()
  @expect.expect((format.name, format.extensions)).to_equal(
    ("JSON5", ["json", "json5"]),
  )
  @expect.expect((format.parse)("{\"a\": 1}", "app.json")).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "a non-object root raises InvalidRoot" {
  @expect.expect(
    expect_error(() => @json5.parse("[1, 2]", origin="numbers.json")),
  ).to_equal(InvalidRoot(origin="numbers.json", found="list"))
}
