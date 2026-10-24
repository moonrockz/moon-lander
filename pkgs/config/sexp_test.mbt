///|
fn sexp(items : Array[@ion.Ion]) -> @config.ConfigValue raise {
  @config.ConfigValue::from_ion(
    @ion.Ion::from_fields([@ion.field("v", @ion.Ion::sexp(items))]),
  )
}

///|
fn annotated(ion : @ion.Ion, name : String) -> @ion.Ion {
  ion.with_annotation(@ion.symbol(name))
}

///|
fn annotation_texts(ion : @ion.Ion) -> Array[String?] {
  ion.annotations().map(token => token.text())
}

///|
fn leaf(value : @config.ConfigValue) -> @ion.Ion {
  guard value.to_ion().kind() is Struct(fields) && fields.length() == 1 else {
    abort("expected one field")
  }
  fields[0].value()
}

///|
test "a sexp replaces a list and a list replaces a sexp" {
  let list = @config.fields([("v", @config.list([@config.int(1)]))])
  let items = sexp([@ion.Ion::Ion(2L), @ion.Ion::Ion(3L)])
  @expect.expect(@config.merge(list, items)).to_equal(items)
  @expect.expect(@config.merge(items, list)).to_equal(list)
}

///|
test "a sexp replaces a struct and a struct replaces a sexp" {
  let table = @config.fields([("v", @config.fields([("a", @config.int(1))]))])
  let items = sexp([@ion.Ion::Ion(2L)])
  @expect.expect(@config.merge(table, items)).to_equal(items)
  @expect.expect(@config.merge(items, table)).to_equal(table)
}

///|
test "get_text writes a sexp as a JSON array" {
  let config = @config.build([
    @config.in_memory(sexp([@ion.Ion::Ion(1L), @ion.Ion::string("x")])),
  ])
  @expect.expect(@config.get_text(config, "v")).to_equal("[1,\"x\"]")
}

///|
test "an overlay scalar or list keeps its own annotations" {
  let base = @config.ConfigValue::from_ion(
    @ion.Ion::from_fields([
      @ion.field("s", annotated(@ion.Ion::string("a"), "base")),
      @ion.field("l", annotated(@ion.Ion::list([]), "base")),
    ]),
  )
  let overlay = @config.ConfigValue::from_ion(
    @ion.Ion::from_fields([
      @ion.field("s", @ion.Ion::string("b")),
      @ion.field("l", annotated(@ion.Ion::sexp([]), "overlay")),
    ]),
  )
  guard @config.merge(base, overlay).to_ion().kind() is Struct(fields) else {
    fail("not a struct")
  }
  @expect.expect(annotation_texts(fields[0].value())).to_equal([])
  @expect.expect(annotation_texts(fields[1].value())).to_equal([Some("overlay")])
}

///|
test "a merged struct keeps the overlay annotations when it has some" {
  let base = @config.ConfigValue::from_ion(
    @ion.Ion::from_fields([
      @ion.field("t", annotated(@ion.Ion::from_fields([]), "base")),
    ]),
  )
  let overlay = @config.ConfigValue::from_ion(
    @ion.Ion::from_fields([
      @ion.field("t", annotated(@ion.Ion::from_fields([]), "overlay")),
    ]),
  )
  @expect.expect(annotation_texts(leaf(@config.merge(base, overlay)))).to_equal([
    Some("overlay"),
  ])
  @expect.expect(
    annotation_texts(leaf(@config.merge(base, @config.fields([("t", @config.fields([]))])))),
  ).to_equal([Some("base")])
}
