///|
fn field_names(value : @config.ConfigValue) -> Array[String] {
  guard value.to_ion().kind() is Struct(fields) else { return [] }
  fields.map(field => field.name().text().unwrap_or(""))
}

///|
fn expect_error(
  run : () -> @config.ConfigValue raise @config.ConfigError,
) -> @config.ConfigError {
  try run() catch {
    error => error
  } noraise {
    value => abort("expected an error, got \{value.type_name()}")
  }
}

///|
test "a JSON root that is not a struct raises an invalid-root error" {
  let json : Json = [1, 2]
  let error = expect_error(() => @config.ConfigValue::from_json(
    json,
    origin="numbers.json",
  ))
  @expect.expect(error).to_equal(
    InvalidRoot(origin="numbers.json", found="list"),
  )
}

///|
test "a JSON object gives a struct with the fields in order" {
  let json : Json = { "b": "1", "a": { "y": true, "x": false }, "c": [1] }
  let value = @config.ConfigValue::from_json(json)
  @expect.expect(field_names(value)).to_equal(["b", "a", "c"])
  guard value.to_ion().kind() is Struct(fields) else { fail("not a struct") }
  @expect.expect(
    field_names(@config.ConfigValue::from_ion(fields[1].value())),
  ).to_equal(["y", "x"])
}

///|
test "to_ion gives the Ion value back" {
  let ion = @ion.Ion::from_fields([@ion.field("a", @ion.Ion::string("x"))])
  @expect.expect(@config.ConfigValue::from_ion(ion).to_ion().equals(ion)).to_equal(
    true,
  )
}

///|
test "a repeated field name raises a duplicate-key error" {
  let ion = @ion.Ion::from_fields([
    @ion.field("a", @ion.Ion::bool(true)),
    @ion.field("a", @ion.Ion::bool(false)),
  ])
  let error = expect_error(() => @config.ConfigValue::from_ion(
    ion,
    origin="app.ion",
  ))
  @expect.expect(error).to_equal(
    DuplicateKey(origin="app.ion", key=@config.KeyPath::parse("a")),
  )
  @expect.expect(error.message()).to_equal(
    "Duplicate configuration key a in app.ion",
  )
}

///|
test "a repeated field name in a nested struct names its key path" {
  let inner = @ion.Ion::from_fields([
    @ion.field("port", @ion.Ion::bool(true)),
    @ion.field("port", @ion.Ion::bool(false)),
  ])
  let nested = @ion.Ion::from_fields([
    @ion.field("servers", @ion.Ion::from_fields([@ion.field("eu.west", inner)])),
  ])
  @expect.expect(
    expect_error(() => @config.ConfigValue::from_ion(nested, origin="app.ion")),
  ).to_equal(
    DuplicateKey(
      origin="app.ion",
      key=@config.KeyPath::parse("servers.\"eu.west\".port"),
    ),
  )
  let in_list = @ion.Ion::from_fields([
    @ion.field("targets", @ion.Ion::sexp([inner])),
  ])
  @expect.expect(
    expect_error(() => @config.ConfigValue::from_ion(in_list, origin="app.ion")),
  ).to_equal(
    DuplicateKey(origin="app.ion", key=@config.KeyPath::parse("targets.port")),
  )
}

///|
test "a field name with no text raises a parse error" {
  let ion = @ion.Ion::from_fields([
    @ion.field(
      "a",
      @ion.Ion::from_fields([
        @ion.Field::from_token(
          @ion.SymbolToken::from_sid(10),
          @ion.Ion::bool(true),
        ),
      ]),
    ),
  ])
  @expect.expect(
    expect_error(() => @config.ConfigValue::from_ion(ion, origin="app.ion")),
  ).to_equal(
    Parse(
      format="Ion",
      origin="app.ion",
      message="the field name $10 in a has no text",
      line=None,
      column=None,
    ),
  )
}

///|
test "fields keeps the last value of a repeated name at its first position" {
  let value = @config.fields([
    ("b", @config.int(1)),
    ("a", @config.int(2)),
    ("b", @config.int(3)),
  ])
  @expect.expect(field_names(value)).to_equal(["b", "a"])
  @expect.expect(value).to_equal(
    @config.fields([("b", @config.int(3)), ("a", @config.int(2))]),
  )
}
