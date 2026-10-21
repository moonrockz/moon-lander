///|
fn names(value : @config.ConfigValue) -> Array[String] {
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
    _ => abort("expected a configuration error")
  }
}

///|
fn library_ion(text : String) -> @ion.Ion {
  let documents = @yaml_lib.Yaml::load_from_string(text[:]) catch {
    @yaml_lib.YamlError(info~, ..) => abort(info)
  }
  guard documents.length() == 1 else {
    abort("library examples use one document")
  }
  yaml_to_ion(documents[0])
}

///|
fn yaml_to_ion(value : @yaml_lib.Yaml) -> @ion.Ion {
  match value {
    Map(fields) =>
      @ion.Ion::from_fields(
        fields
        .to_array()
        .map(entry => @ion.field(entry.0, yaml_to_ion(entry.1))),
      )
    Array(items) => @ion.Ion::list(items.map(yaml_to_ion))
    String(text) => @ion.Ion::string(text)
    Integer(number) => @ion.Ion::big_int(@bigint.BigInt::from_int64(number))
    Real(number, ..) => @ion.Ion::float(number)
    Boolean(flag) => @ion.Ion::bool(flag)
    Null => @ion.Ion::untyped_null()
    BadValue => abort("library BadValue")
  }
}

///|
test "Core schema scalars" {
  let text =
    #|a: true
    #|b: 42
    #|c: 1.5
    #|d: yes
    #|e: "42"
    #|f: 2026-09-28
  let value = @yaml.parse(text, origin="app.yaml")
  @expect.expect(value).to_equal(
    @config.fields([
      ("a", @config.bool(true)),
      ("b", @config.int(42)),
      ("c", @config.float(1.5)),
      ("d", @config.string("yes")),
      ("e", @config.string("42")),
      ("f", @config.string("2026-09-28")),
    ]),
  )
}

///|
test "the event builder matches Yaml::load_from_string on library examples" {
  for text in [
    "a: 1\nb: 'q'\n",
    "a: true\nb: false\nc: null\nd: ~\n",
    "a: 0x2A\nb: 0o52\nc: +7\n",
    "list:\n  - 1\n  - two\n  - true\n",
    "nested:\n  x: 1\n  y: [a, b]\n",
  ] {
    let built = @yaml.parse(text, origin="app.yaml").to_ion()
    let library = library_ion(text)
    @expect.expect(built.equals(library)).to_equal(true)
  }
}

///|
test "YAML integers above Int64 stay exact" {
  let text = "big: 9223372036854775808\n"
  let value = @yaml.parse(text, origin="app.yaml")
  guard value.to_ion().kind() is Struct(fields) else { fail("expected a mapping") }
  guard fields[0].value().kind() is Int(number) else { fail("expected an int") }
  @expect.expect(number.to_string()).to_equal("9223372036854775808")
}

///|
test "More than one document" {
  let error = expect_error(() =>
    @yaml.parse("a: 1\n---\nb: 2\n", origin="/w/app.yaml")
  )
  guard error is Parse(origin~, line~, ..) else { fail("expected Parse") }
  @expect.expect(origin).to_equal("/w/app.yaml")
  @expect.expect(line).to_equal(Some(2))
}

///|
test "Duplicate key" {
  let error = expect_error(() =>
    @yaml.parse("name: a\nname: b\n", origin="/w/app.yaml")
  )
  guard error is Parse(origin~, message~, line~, column~, ..) else {
    fail("expected Parse")
  }
  @expect.expect(origin).to_equal("/w/app.yaml")
  @expect.expect(message).to_equal("duplicate key name")
  @expect.expect(line is Some(_)).to_equal(true)
  @expect.expect(column is Some(_)).to_equal(true)
}

///|
test "Merge key" {
  let error = expect_error(() => @yaml.parse("<<: a\n", origin="/w/app.yaml"))
  guard error is UnsupportedYaml(origin~, feature~, line~, ..) else {
    fail("expected UnsupportedYaml")
  }
  @expect.expect((origin, feature)).to_equal(("/w/app.yaml", "merge key"))
  @expect.expect(line > 0).to_equal(true)
}

///|
test "Default profile accepts an alias" {
  let text =
    #|a: &x 1
    #|b: *x
  let value = @yaml.parse(text, origin="app.yaml")
  @expect.expect(value).to_equal(
    @config.fields([("a", @config.int(1)), ("b", @config.int(1))]),
  )
}

///|
test "empty document is an empty struct" {
  let value = @yaml.parse("", origin="app.yaml")
  @expect.expect(names(value)).to_equal([])
}

///|
test "the YAML format selects yaml and yml" {
  let format = @yaml.format()
  @expect.expect((format.name, format.extensions)).to_equal(
    ("YAML", ["yaml", "yml"]),
  )
  @expect.expect((format.parse)("a: 1\n", "app.yaml")).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "Strict profile rejects an alias" {
  let text =
    #|a: &x 1
    #|b: *x
  let error = expect_error(() =>
    @yaml.parse(text, origin="/w/app.yaml", profile=Strict)
  )
  guard error is UnsupportedYaml(origin~, feature~, line~, column~) else {
    fail("expected UnsupportedYaml")
  }
  @expect.expect((origin, feature)).to_equal(("/w/app.yaml", "anchor"))
  @expect.expect(line > 0).to_equal(true)
  @expect.expect(column >= 0).to_equal(true)
}

///|
test "Strict profile rejects null" {
  let error = expect_error(() =>
    @yaml.parse("a: ~\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is UnsupportedYaml(origin~, feature~, ..) else {
    fail("expected UnsupportedYaml")
  }
  @expect.expect((origin, feature)).to_equal(("/w/app.yaml", "a"))
}

///|
test "Strict profile rejects an anchor" {
  let error = expect_error(() =>
    @yaml.parse("a: &x 1\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is UnsupportedYaml(feature~, ..) else {
    fail("expected UnsupportedYaml")
  }
  @expect.expect(feature).to_equal("anchor")
}

///|
test "Strict profile rejects a custom tag" {
  let error = expect_error(() =>
    @yaml.parse("a: !foo bar\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is UnsupportedYaml(feature~, ..) else {
    fail("expected UnsupportedYaml")
  }
  @expect.expect(feature.contains("foo") || feature != "anchor").to_equal(true)
}

///|
test "Strict profile rejects a merge key" {
  let error = expect_error(() =>
    @yaml.parse("<<: a\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is UnsupportedYaml(feature~, ..) else {
    fail("expected UnsupportedYaml")
  }
  @expect.expect(feature).to_equal("merge key")
}

///|
test "Strict profile rejects a duplicate key" {
  let error = expect_error(() =>
    @yaml.parse("name: a\nname: b\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is Parse(message~, ..) else { fail("expected Parse") }
  @expect.expect(message).to_equal("duplicate key name")
}

///|
test "Strict profile rejects more than one document" {
  let error = expect_error(() =>
    @yaml.parse("a: 1\n---\nb: 2\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is Parse(message~, ..) else { fail("expected Parse") }
  @expect.expect(message).to_equal("expected exactly one YAML document")
}

///|
test "Strict profile rejects a non-mapping root" {
  let error = expect_error(() =>
    @yaml.parse("- 1\n- 2\n", origin="/w/app.yaml", profile=Strict)
  )
  guard error is UnsupportedYaml(origin~, feature~, line~, column~) else {
    fail("expected UnsupportedYaml with a source mark")
  }
  @expect.expect(origin).to_equal("/w/app.yaml")
  @expect.expect(feature).to_equal("non-mapping root")
  @expect.expect(line > 0).to_equal(true)
  @expect.expect(column >= 0).to_equal(true)
}

///|
test "Default profile rejects a non-mapping root" {
  let error = expect_error(() => @yaml.parse("- 1\n", origin="app.yaml"))
  guard error is InvalidRoot(found~, ..) else { fail("expected InvalidRoot") }
  @expect.expect(found).to_equal("list")
}

///|
test "empty string mapping keys are kept" {
  let value = @yaml.parse("\"\": kept\n", origin="app.yaml")
  @expect.expect(value).to_equal(
    @config.fields([("", @config.string("kept"))]),
  )
}

///|
test "invalid radix digits stay strings" {
  let value = @yaml.parse("id: 0xnode\n", origin="app.yaml")
  @expect.expect(value).to_equal(
    @config.fields([("id", @config.string("0xnode"))]),
  )
}

///|
test "signed radix forms stay strings" {
  let value = @yaml.parse("a: -0x2A\nb: +0o52\n", origin="app.yaml")
  @expect.expect(value).to_equal(
    @config.fields([
      ("a", @config.string("-0x2A")),
      ("b", @config.string("+0o52")),
    ]),
  )
}

///|
test "explicit !!int keeps radix forms" {
  let value = @yaml.parse(
    "a: !!int 0x2A\nb: !!int -0o52\n",
    origin="app.yaml",
  )
  @expect.expect(value).to_equal(
    @config.fields([("a", @config.int(42)), ("b", @config.int(-42))]),
  )
}
