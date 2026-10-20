///|
fn key(text : String) -> @config.KeyPath {
  @config.KeyPath::parse(text) catch {
    err => abort("bad test key \{text}: \{err.message()}")
  }
}

///|
fn tree(fields : Array[(String, @config.ConfigValue)]) -> @config.ConfigValue {
  @config.fields(fields)
}

///|
fn names(value : @config.ConfigValue) -> Array[String] {
  guard value.to_ion().kind() is Struct(fields) else { return [] }
  fields.map(field => field.name().text().unwrap_or(""))
}

///|
test "get finds a value at a key path" {
  let config = @config.build([
    @config.in_memory_pairs([("project.name", @config.string("demo"))]),
  ])
  @expect.expect(config.get(key("project.name"))).to_equal(
    Some(@config.string("demo")),
  )
}

///|
test "get gives no value for a missing key" {
  let config = @config.build([
    @config.in_memory_pairs([("project.name", @config.string("demo"))]),
  ])
  @expect.expect(config.get(key("project.missing"))).to_equal(None)
  @expect.expect(config.get(key("project.name.deeper"))).to_equal(None)
}

///|
test "a source root must be a struct" {
  try
    @config.in_memory(
      @config.list([@config.int(1), @config.int(2)]),
      name="numbers",
    )
  catch {
    error =>
      @expect.expect(error).to_equal(InvalidRoot(origin="numbers", found="list"))
  } noraise {
    _ => fail("expected a list root to raise")
  }
}

///|
test "flat key-path pairs give nested structs" {
  let config = @config.build([
    @config.in_memory_pairs([
      ("ir.layout", @config.string("single-file")),
      ("ir.strict_mode", @config.bool(true)),
    ]),
  ])
  @expect.expect(config.value()).to_equal(
    tree([
      (
        "ir",
        tree([
          ("layout", @config.string("single-file")),
          ("strict_mode", @config.bool(true)),
        ]),
      ),
    ]),
  )
}

///|
test "a later pair wins" {
  let config = @config.build([
    @config.in_memory_pairs([
      ("a.b", @config.int(1)),
      ("a", @config.string("x")),
    ]),
  ])
  @expect.expect(config.value()).to_equal(tree([("a", @config.string("x"))]))
}

///|
test "a pair with a bad key path raises" {
  try @config.in_memory_pairs([("a..b", @config.int(1))]) catch {
    InvalidKeyPath(..) => ()
    _ => fail("expected InvalidKeyPath")
  } noraise {
    _ => fail("expected a bad key path to raise")
  }
}

///|
test "an in-memory source takes a value tree" {
  let value = tree([("port", @config.string("8080"))])
  let config = @config.build([@config.in_memory(value)])
  @expect.expect(config.value()).to_equal(value)
}

///|
test "a later source wins" {
  let config = @config.build([
    @config.in_memory_pairs([("ir.layout", @config.string("tree"))]),
    @config.in_memory_pairs([("ir.layout", @config.string("single-file"))]),
  ])
  @expect.expect(config.get(key("ir.layout"))).to_equal(
    Some(@config.string("single-file")),
  )
}

///|
test "structs merge and arrays replace" {
  let base = tree([
    (
      "project",
      tree([
        ("name", @config.string("Base")),
        (
          "exposed_modules",
          @config.list([@config.string("A"), @config.string("B")]),
        ),
      ]),
    ),
  ])
  let overlay = tree([
    (
      "project",
      tree([("exposed_modules", @config.list([@config.string("C")]))]),
    ),
  ])
  let expected = tree([
    (
      "project",
      tree([
        ("name", @config.string("Base")),
        ("exposed_modules", @config.list([@config.string("C")])),
      ]),
    ),
  ])
  @expect.expect(@config.merge(base, overlay)).to_equal(expected)
  let config = @config.build([
    @config.in_memory(base),
    @config.in_memory(overlay),
  ])
  @expect.expect(config.value()).to_equal(expected)
}

///|
test "new overlay fields follow base fields" {
  let merged = @config.merge(
    tree([("b", @config.int(1)), ("a", @config.int(2))]),
    tree([("c", @config.int(3)), ("a", @config.int(4))]),
  )
  @expect.expect(names(merged)).to_equal(["b", "a", "c"])
  @expect.expect(merged).to_equal(
    tree([
      ("b", @config.int(1)),
      ("a", @config.int(4)),
      ("c", @config.int(3)),
    ]),
  )
}

///|
test "a scalar replaces a struct" {
  let merged = @config.merge(
    tree([("ir", tree([("layout", @config.string("tree"))]))]),
    tree([("ir", @config.string("x"))]),
  )
  @expect.expect(merged).to_equal(tree([("ir", @config.string("x"))]))
}

///|
test "an empty build gives an empty struct" {
  @expect.expect(@config.build([]).value()).to_equal(tree([]))
}

///|
test "get_text writes a string as its text" {
  let config = @config.build([
    @config.in_memory_pairs([
      ("project.name", @config.string("acceptance-project")),
    ]),
  ])
  @expect.expect(@config.get_text(config, "project.name")).to_equal(
    "acceptance-project",
  )
}

///|
test "get_text writes other values as JSON" {
  let config = @config.build([
    @config.in_memory_pairs([
      ("ir.format_version", @config.int(4)),
      ("ir.strict_mode", @config.bool(true)),
    ]),
  ])
  @expect.expect(@config.get_text(config, "ir.format_version")).to_equal("4")
  @expect.expect(@config.get_text(config, "ir")).to_equal(
    "{\"format_version\":4,\"strict_mode\":true}",
  )
}

///|
test "get_text raises key-not-found for a missing key" {
  let config = @config.build([])
  try @config.get_text(config, "project.missing") catch {
    error => {
      guard error is KeyNotFound(_) else { fail("wrong error") }
      @expect.expect(error.message()).to_equal(
        "Configuration key not found: project.missing",
      )
    }
  } noraise {
    _ => fail("expected a missing key to raise")
  }
}

///|
test "a merged struct keeps the base annotations when the overlay has none" {
  let base = @config.ConfigValue::from_ion(
    @ion.Ion::from_fields([]).with_annotation(@ion.symbol("app")),
  )
  let merged = @config.merge(base, @config.fields([("a", @config.int(1))]))
  @expect.expect(merged.to_ion().annotations().map(token => token.text())).to_equal(
    [Some("app")],
  )
}

///|
test "a value tree from Ion must have a struct root" {
  try @config.ConfigValue::from_ion(@ion.Ion::list([]), origin="numbers") catch {
    error =>
      @expect.expect(error).to_equal(InvalidRoot(origin="numbers", found="list"))
  } noraise {
    _ => fail("expected a list root to raise")
  }
}
