///|
/// Draft-07 core section 8.2.4 example.
fn spec_example() -> @reference.SchemaIndex {
  let value = json_value(
    "{\"$id\":\"http://example.com/root.json\",\"definitions\":{\"A\":{\"$id\":\"#foo\"},\"B\":{\"$id\":\"other.json\",\"definitions\":{\"X\":{\"$id\":\"#bar\"},\"Y\":{\"$id\":\"t/inner.json\"}}},\"C\":{\"$id\":\"urn:uuid:ee564b8a-7a87-4125-8c96-e9f123d6766f\"}}}",
  )
  let resource = @reference.Resource::new(
    uri("https://retrieved.example/root.json"),
    value,
    schema_roots=[@reference.JsonPointer::parse("").unwrap()],
  ).unwrap()
  @reference.SchemaIndex::new(@reference.ResourceSet::new([resource]).unwrap())
}

///|
fn located(
  index : @reference.SchemaIndex,
  text : String,
) -> Array[String] raise {
  let found = index.resolve(ref_(text))
  assert_true(found.complete(), msg=text)
  let target = found.target().unwrap()
  assert_eq(
    target.resource().unwrap().text(),
    "https://retrieved.example/root.json",
  )
  target.pointer().tokens()
}

///|
test "draft-07 identifiers from section 8.2.4 name their owned locations" {
  let index = spec_example()
  assert_true(index.complete())
  assert_eq(index.diagnostics().length(), 0)
  for
    (text, expected) in [
      ("http://example.com/root.json", []),
      ("http://example.com/root.json#", []),
      (
        "https://retrieved.example/root.json#/definitions/A",
        ["definitions", "A"],
      ),
      ("http://example.com/root.json#foo", ["definitions", "A"]),
      ("http://example.com/root.json#/definitions/A", ["definitions", "A"]),
      ("http://example.com/other.json", ["definitions", "B"]),
      (
        "http://example.com/other.json#/definitions/X",
        ["definitions", "B", "definitions", "X"],
      ),
      (
        "http://example.com/other.json#bar",
        ["definitions", "B", "definitions", "X"],
      ),
      (
        "http://example.com/root.json#/definitions/B/definitions/X",
        ["definitions", "B", "definitions", "X"],
      ),
      (
        "http://example.com/t/inner.json",
        ["definitions", "B", "definitions", "Y"],
      ),
      ("urn:uuid:ee564b8a-7a87-4125-8c96-e9f123d6766f", ["definitions", "C"]),
    ] {
    assert_eq(located(index, text), expected, msg=text)
  }
}

///|
test "relative references resolve against the nearest identifier scope" {
  let index = spec_example()
  let b = index
    .resolve(ref_("http://example.com/root.json#/definitions/B"))
    .target()
    .unwrap()
  let scope = index.scope(b).unwrap()
  assert_eq(scope.text(), "http://example.com/other.json")
  let x = index.resolve(ref_("#/definitions/X"), base=Some(scope))
  assert_eq(x.target().unwrap().pointer().tokens(), [
    "definitions", "B", "definitions", "X",
  ])
  let inner = index.resolve(ref_("t/inner.json"), base=Some(scope))
  assert_eq(inner.target().unwrap().pointer().tokens(), [
    "definitions", "B", "definitions", "Y",
  ])
  assert_eq(
    index.resolve(ref_("#")).diagnostics()[0].code(),
    @json.MissingBaseUri,
  )
  let root = index
    .resolve(ref_("https://retrieved.example/root.json#"))
    .target()
    .unwrap()
  assert_eq(index.scope(root).unwrap().text(), "http://example.com/root.json")
  assert_true(
    index.resolve(ref_("#/definitions/X"), base=index.scope(root)).target()
    is None,
  )
}

///|
test "ref siblings, literals and foreign dialects establish no scopes" {
  let value = json_value(
    "{\"definitions\":{\"r\":{\"$ref\":\"#/definitions/s\",\"$id\":\"http://sibling.test/\"},\"s\":{\"const\":{\"$id\":\"http://literal.test/\"},\"default\":{\"$id\":\"#lit\"},\"x-vendor\":{\"$id\":\"http://vendor.test/\"}},\"f\":{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$id\":\"http://foreign.test/\",\"$defs\":{\"g\":{\"$id\":\"#g\"}}}}}",
  )
  let index = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(value),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
  )
  assert_true(index.complete())
  for
    text in [
      "http://sibling.test/", "http://literal.test/", "http://vendor.test/", "http://foreign.test/",
    ] {
    let found = index.resolve(ref_(text))
    assert_eq(
      found.diagnostics()[0].code(),
      @json.UnavailableResource,
      msg=text,
    )
  }
  let lit = index.resolve(ref_("#lit"))
  assert_true(lit.complete())
  assert_eq(lit.diagnostics()[0].code(), @json.UnresolvedReference)
  let own = index.resolve(ref_("#/definitions/s")).target().unwrap()
  assert_true(own.resource() is None)
  assert_eq(own.identity(), "#/definitions/s")
}

///|
test "conflicting identifiers, undefined fragments and missing bases are findings" {
  let duplicated = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(
      json_value(
        "{\"definitions\":{\"a\":{\"$id\":\"http://dup.test/s.json\"},\"b\":{\"$id\":\"HTTP://dup.test/./s.json\"},\"c\":{\"$id\":\"http://dup.test/n.json#n\"},\"d\":{\"$id\":\"http://dup.test/n.json#n\"}}}",
      ),
    ),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
  )
  let codes = duplicated.diagnostics().map(d => d.code())
  assert_eq(codes, [@json.ConflictingIdentifier, @json.ConflictingIdentifier])
  assert_eq(
    duplicated
    .resolve(ref_("http://dup.test/s.json"))
    .target()
    .unwrap()
    .pointer()
    .tokens(),
    ["definitions", "a"],
  )
  let fragment_form = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(json_value("{\"$id\":\"http://u.test/a.json#/pointer\"}")),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
  )
  assert_false(fragment_form.complete())
  assert_eq(fragment_form.diagnostics()[0].code(), @json.UnsupportedCheck)
  assert_true(
    fragment_form.resolve(ref_("http://u.test/a.json")).target() is Some(_),
  )
  let relative = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(
      json_value(
        "{\"$id\":\"child.json\",\"definitions\":{\"n\":{\"$id\":\"#n\"},\"m\":{\"$id\":\"https://abs.test/m.json\",\"definitions\":{\"k\":true}}}}",
      ),
    ),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
  )
  assert_true(relative.complete())
  assert_eq(relative.diagnostics().length(), 0)
  let root = relative.resolve(ref_("#")).target().unwrap()
  let scope = relative.scope(root)
  assert_eq(scope.unwrap().text(), "child.json")
  for text in ["#n", "#/definitions/n"] {
    let found = relative.resolve(ref_(text), base=scope)
    assert_eq(
      found.target().map(t => t.pointer().tokens()),
      Some(["definitions", "n"]),
      msg=text,
    )
  }
  let other = relative.resolve(ref_("other.json"), base=scope)
  assert_false(other.complete())
  assert_eq(other.diagnostics()[0].code(), @json.MissingBaseUri)
  assert_true(
    relative.resolve(ref_("https://abs.test/m.json#/definitions/k")).target()
    is Some(_),
  )
  assert_eq(
    @reference.schema_scope(uri("other.json"), Some(uri("child.json")))
    .unwrap()
    .text(),
    "other.json",
  )
  assert_eq(
    @reference.schema_scope(uri("child.json#x"), None).unwrap().text(),
    "child.json",
  )
}

///|
test "identifiers may not claim another registered resource" {
  let first = @reference.Resource::new(
    uri("https://example.test/a.json"),
    json_value("{}"),
    schema_roots=[@reference.JsonPointer::parse("").unwrap()],
  ).unwrap()
  let second = @reference.Resource::new(
    uri("https://example.test/b.json"),
    json_value(
      "{\"$id\":\"https://example.test/b.json\",\"definitions\":{\"x\":{\"$id\":\"a.json\"}}}",
    ),
    schema_roots=[@reference.JsonPointer::parse("").unwrap()],
  ).unwrap()
  let index = @reference.SchemaIndex::new(
    @reference.ResourceSet::new([first, second]).unwrap(),
  )
  assert_eq(index.diagnostics().map(d => d.code()), [
    @json.ConflictingIdentifier,
  ])
  assert_eq(
    index
    .resolve(ref_("https://example.test/a.json"))
    .target()
    .unwrap()
    .resource()
    .unwrap()
    .text(),
    "https://example.test/a.json",
  )
}

///|
test "schema indexing is bounded" {
  let members = []
  for i in 0..<50 {
    members.push("\"d\{i}\":{\"$id\":\"#n\{i}\"}")
  }
  let value = json_value("{\"definitions\":{" + members.join(",") + "}}")
  let index = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(value),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
    limits=@json.Limits::new(max_nodes=10),
  )
  assert_false(index.complete())
  assert_true(index.diagnostics().any(d => d.code() == @json.LimitExceeded))
}

///|
test "plain names resolve through every spelling of their scope document" {
  let resource = @reference.Resource::new(
    uri("https://a.test/s.json"),
    json_value(
      "{\"$id\":\"https://id.test/root.json\",\"definitions\":{\"A\":{\"$id\":\"#foo\"}}}",
    ),
    aliases=[uri("https://alias.test/s.json")],
    schema_roots=[@reference.JsonPointer::parse("").unwrap()],
  ).unwrap()
  let index = @reference.SchemaIndex::new(
    @reference.ResourceSet::new([resource]).unwrap(),
  )
  for
    text in [
      "https://a.test/s.json#foo", "https://alias.test/s.json#foo", "https://id.test/root.json#foo",
    ] {
    let found = index.resolve(ref_(text))
    assert_eq(
      found.target().map(t => t.pointer().tokens()),
      Some(["definitions", "A"]),
      msg=text,
    )
  }
}

///|
test "identifier scopes do not depend on schema root declaration order" {
  let value = json_value(
    "{\"$id\":\"http://x.test/root.json\",\"definitions\":{\"a\":{\"$id\":\"a.json\"}}}",
  )
  for roots in [["", "/definitions/a"], ["/definitions/a", ""]] {
    let resource = @reference.Resource::new(
      uri("https://r.test/doc.json"),
      value,
      schema_roots=roots.map(p => @reference.JsonPointer::parse(p).unwrap()),
    ).unwrap()
    let index = @reference.SchemaIndex::new(
      @reference.ResourceSet::new([resource]).unwrap(),
    )
    assert_true(
      index.resolve(ref_("http://x.test/a.json")).target() is Some(_),
      msg=roots.join(","),
    )
    assert_true(
      index.resolve(ref_("https://r.test/a.json")).target() is None,
      msg=roots.join(","),
    )
  }
}

///|
test "fragment-only references resolve inside a relative identifier scope" {
  let index = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(
      json_value(
        "{\"definitions\":{\"s\":{\"$id\":\"s.json\",\"definitions\":{\"x\":{\"$id\":\"#x\"}}}}}",
      ),
    ),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
  )
  assert_true(index.complete())
  let s = index.resolve(ref_("#/definitions/s")).target().unwrap()
  let scope = index.scope(s)
  for text in ["#/definitions/x", "#x", "#"] {
    let found = index.resolve(ref_(text), base=scope)
    assert_true(found.complete(), msg=text)
    assert_true(found.target() is Some(_), msg=text)
  }
  assert_eq(
    index
    .resolve(ref_("#/definitions/x"), base=scope)
    .target()
    .unwrap()
    .pointer()
    .tokens(),
    ["definitions", "s", "definitions", "x"],
  )
  let other = index.resolve(ref_("other.json#/a"), base=scope)
  assert_false(other.complete())
  assert_eq(other.diagnostics()[0].code(), @json.MissingBaseUri)
}
