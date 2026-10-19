///|
test "Ion metadata imports and exports isolate containers and annotations" {
  let items = [@ion.Ion::int(1)]
  let annotations = [@ion.symbol("tag")]
  let fields = [@ion.field("vendor", @ion.Ion::list(items).with_annotations(annotations))]
  let root_annotations = [@ion.symbol("root")]
  let input = @ion.Ion::from_fields(fields).with_annotations(root_annotations)
  let metadata = @notebooks.Metadata::from_ion(input)
  let expected = @ion_text.read_ion("root::{vendor: tag::[1]}")
  items.clear()
  annotations.clear()
  fields.clear()
  root_annotations.clear()
  guard metadata.get("vendor") is Some(exported) else { fail("missing vendor") }
  guard exported.kind() is List(values) else { fail("expected list") }
  values.clear()
  exported.annotations().clear()
  let output = metadata.to_ion()
  output.annotations().clear()
  guard output.kind() is Struct(output_fields) else { fail("expected struct") }
  output_fields.clear()
  @expect.expect_all(s => {
    s.expect(metadata.to_ion().equals(expected)).to_be_true()
    s.expect(metadata.keys()).to_equal(["vendor"])
    s.expect(metadata.is_empty()).to_be_false()
    s.expect(metadata.get("missing") is None).to_be_true()
  })
}

///|
test "native metadata retains richer Ion types and rejects lossy JSON exports" {
  let value = @ion_text.read_ion(
    "{title: \"Example\", typed: null.int, decimal: 1234.500, when: 2026-10-19T12:00:00Z, nested: {a: 1, a: 2}, symbol: foo, bytes: {{aGVsbG8=}}, sexp: (1 2), special: nan}",
  )
  let metadata = @notebooks.Metadata::from_ion(value)
  @expect.expect(metadata.to_ion().equals(value)).to_be_true()
  @expect.expect(metadata.get_json("title")).to_equal(Some("Example"))
  guard metadata.get("typed") is Some(typed) else { fail("typed null missing") }
  @expect.expect(typed.kind() is Null(@ion.IonType::Int)).to_be_true()
  guard metadata.get("decimal") is Some(decimal) else { fail("decimal missing") }
  guard decimal.kind() is Decimal(number) else { fail("expected decimal") }
  @expect.expect(number.to_ion_string()).to_equal("1234.500")
  @expect.expect(metadata.get_json("decimal").map(value => value.stringify())).to_equal(Some("1234.500"))
  for key in ["typed", "when", "nested", "symbol", "bytes", "sexp", "special"] {
    try metadata.get_json(key) catch {
      @notebooks.NotJson(path~, ..) => @expect.expect(path).to_equal("$." + key)
      _ => fail("expected a JSON conversion error")
    } noraise {
      _ => fail("expected lossy conversion to be rejected")
    }
  }
}

///|
test "metadata rejects duplicate or unknown top-level Ion field names" {
  for input in [
    @ion_text.read_ion("{a: 1, a: 2}"),
    @ion.Ion::from_fields([
      @ion.Field::from_token(@ion.SymbolToken::from_sid(99), @ion.Ion::int(1)),
    ]),
  ] {
    try @notebooks.Metadata::from_ion(input) catch {
      @notebooks.InvalidKey(_) => ()
      _ => fail("expected invalid metadata keys")
    } noraise { _ => fail("expected invalid metadata to raise") }
  }
}

///|
test "Jupyter boundaries reject metadata that requires Ion" {
  let metadata = @notebooks.Metadata::from_ion(
    @ion_text.read_ion("{when: 2026-10-19T12:00:00Z}"),
  )
  try @nbformat.Notebook::Notebook([], metadata~) catch {
    @nbformat.InvalidField(path~, ..) => @expect.expect(path).to_equal("$.metadata")
    _ => fail("expected a metadata field error")
  } noraise { _ => fail("expected Jupyter's JSON boundary to reject timestamp metadata") }
}

///|
test "large decimal exponents stay compact during JSON conversion and DIB selection" {
  let metadata = @notebooks.Metadata::from_ion(@ion_text.read_ion("{number: 1d1000000}"))
  @expect.expect(metadata.get_json("number").map(value => value.stringify())).to_equal(Some("1e1000000"))
  let book = @dib.Notebook::Notebook([], metadata~)
  @expect.expect(book.to_string().has_prefix("#!meta ion\n")).to_be_true()
  @expect.expect(@dib.parse(book.to_string()).metadata()).to_equal(metadata)
}
