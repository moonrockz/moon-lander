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
test "Ion keeps exact values" {
  let text =
    #|{ price: 1.10, at: 2026-09-28T12:30Z, kind: 'fast', n: 123456789012345678901234567890 }
  let value = @ion.parse(text, origin="app.ion")
  guard value.to_ion().kind() is Struct(fields) else { fail("expected a struct") }
  let by_name = Map::from_iter(
    fields.iter().map(field => (field.name().text().unwrap(), field.value())),
  )
  guard by_name.get("price").unwrap().kind() is Decimal(decimal) else {
    fail("price should be a decimal")
  }
  @expect.expect(decimal.to_ion_string()).to_equal("1.10")
  guard by_name.get("at").unwrap().kind() is Timestamp(timestamp) else {
    fail("at should be a timestamp")
  }
  @expect.expect(timestamp.to_ion_string()).to_equal("2026-09-28T12:30Z")
  guard by_name.get("kind").unwrap().kind() is Symbol(token) else {
    fail("kind should be a symbol")
  }
  @expect.expect(token.text()).to_equal(Some("fast"))
  guard by_name.get("n").unwrap().kind() is Int(number) else {
    fail("n should be an integer")
  }
  @expect.expect(number.to_string()).to_equal(
    "123456789012345678901234567890",
  )
}

///|
test "Ion repeated field" {
  @expect.expect(
    expect_error(() => @ion.parse("{ a: 1, a: 2 }", origin="app.ion")),
  ).to_equal(DuplicateKey(origin="app.ion", key=@config.KeyPath::parse("a")))
}

///|
test "Ion with two top-level values" {
  @expect.expect(
    expect_error(() => @ion.parse("{ a: 1 } { b: 2 }", origin="app.ion")),
  ).to_equal(InvalidRoot(origin="app.ion", found="datagram"))
}

///|
test "the Ion format selects the ion extension" {
  let format = @ion.format()
  @expect.expect((format.name, format.extensions)).to_equal(("Ion", ["ion"]))
  @expect.expect((format.parse)("{ a: 1 }", "app.ion")).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "All formats give the same tree" {
  let toml_text =
    #|[ir]
    #|layout = "single-file"
    #|strict_mode = true
  let yaml_text =
    #|ir:
    #|  layout: single-file
    #|  strict_mode: true
  let json_text =
    #|{"ir": {"layout": "single-file", "strict_mode": true}}
  let ion_text =
    #|{ir: {layout: "single-file", strict_mode: true}}
  let expected = @config.fields([
    (
      "ir",
      @config.fields([
        ("layout", @config.string("single-file")),
        ("strict_mode", @config.bool(true)),
      ]),
    ),
  ])
  @expect.expect(@toml.parse(toml_text, origin="app.toml")).to_equal(expected)
  @expect.expect(@yaml.parse(yaml_text, origin="app.yaml")).to_equal(expected)
  @expect.expect(@json5.parse(json_text, origin="app.json")).to_equal(expected)
  @expect.expect(@ion.parse(ion_text, origin="app.ion")).to_equal(expected)
}
