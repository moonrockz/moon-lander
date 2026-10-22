///|
fn doc(body : String) -> @openrpc.Document {
  @openrpc.read(
    "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"}," +
    body +
    "}",
  )
  .document()
  .unwrap()
}

///|
fn exact(text : String) -> @exact.Value {
  @exact.parse(text).unwrap().lower().unwrap()
}

///|
fn uri(text : String) -> @reference.UriReference {
  @reference.UriReference::parse(text).unwrap()
}

///|
fn reference_errors(report : @openrpc.ValidationReport) -> Array[@exact.Code] {
  report
  .findings()
  .filter(f => {
    f.phase() == @openrpc.References && f.severity() == @openrpc.Error
  })
  .map(f => f.diagnostic().code())
}

///|
let all_sites : String = "\"methods\":[{\"name\":\"op\",\"params\":[{\"$ref\":\"#/components/contentDescriptors/P\"}],\"result\":{\"$ref\":\"#/components/contentDescriptors/R\"},\"errors\":[{\"$ref\":\"#/components/errors/E\"}],\"links\":[{\"$ref\":\"#/components/links/L\"}],\"tags\":[{\"$ref\":\"#/components/tags/T\"}],\"examples\":[{\"$ref\":\"#/components/examplePairings/X\"}]}],\"components\":{\"contentDescriptors\":{\"P\":{\"name\":\"p\",\"schema\":{\"$ref\":\"#/components/schemas/S\"}},\"R\":{\"name\":\"r\",\"schema\":true}},\"schemas\":{\"S\":{\"type\":\"object\",\"properties\":{\"next\":{\"$ref\":\"#/components/schemas/S\"}}}},\"errors\":{\"E\":{\"code\":1,\"message\":\"bad\",\"data\":{\"$ref\":\"https://evil.invalid/data\"}}},\"links\":{\"L\":{\"name\":\"l\"}},\"tags\":{\"T\":{\"name\":\"t\"}},\"examples\":{\"Ex\":{\"name\":\"ex\",\"value\":{\"$ref\":\"#/nowhere\"}}},\"examplePairings\":{\"X\":{\"name\":\"x\",\"params\":[{\"$ref\":\"#/components/examples/Ex\"}],\"result\":{\"$ref\":\"#/components/examples/Ex\"}}}}"

///|
test "every OpenRPC reference site resolves to its expected object kind" {
  let report = @openrpc.validate(doc(all_sites))
  assert_eq(reference_errors(report), [])
  assert_eq(report.references(), @openrpc.Passed)
  assert_eq(report.schemas(), @openrpc.Passed)
}

///|
test "wrong-kind and broken object targets fail with distinct codes" {
  for
    (from, to, code) in [
      (
        "#/components/contentDescriptors/P",
        "#/components/errors/E",
        @exact.WrongType,
      ),
      ("#/components/errors/E", "#/components/tags/T", @exact.WrongType),
      ("#/components/links/L", "#/components/errors/E/code", @exact.WrongType),
      ("#/components/tags/T", "#/components/errors/E", @exact.WrongType),
      (
        "#/components/examplePairings/X",
        "#/components/tags/T",
        @exact.WrongType,
      ),
      (
        "#/components/examples/Ex",
        "#/components/schemas/S/type",
        @exact.WrongType,
      ),
      (
        "#/components/errors/E",
        "#/components/errors/Missing",
        @exact.UnresolvedReference,
      ),
    ] {
    let report = @openrpc.validate(doc(all_sites.replace(old=from, new=to)))
    assert_eq(
      reference_errors(report).get(0),
      Some(code),
      msg=from + " -> " + to,
    )
    assert_eq(report.references(), @openrpc.Failed, msg=from)
  }
}

///|
test "reference-only object cycles fail" {
  for
    methods in [
      "[{\"$ref\":\"#/methods/0\"}]", "[{\"$ref\":\"#/methods/1\"},{\"$ref\":\"#/methods/0\"}]",
    ] {
    let report = @openrpc.validate(doc("\"methods\":" + methods))
    assert_true(
      reference_errors(report).contains(@exact.ReferenceCycle),
      msg=methods,
    )
    assert_eq(report.references(), @openrpc.Failed)
  }
}

///|
let external_methods : String = "{\"m\":{\"name\":\"ext\",\"params\":[{\"$ref\":\"#/p\"}],\"result\":{\"name\":\"r\",\"schema\":{\"$ref\":\"#/s\"}}},\"p\":{\"name\":\"a\",\"schema\":{\"type\":\"string\"}},\"s\":{\"type\":\"integer\",\"items\":{\"$ref\":\"#/s\"}}}"

///|
test "external objects and schemas resolve only from supplied resources" {
  let document = doc(
    "\"methods\":[{\"$ref\":\"https://ext.test/methods.json#/m\"}]",
  )
  let open = @openrpc.validate(document)
  assert_eq(open.references(), @openrpc.Incomplete)
  assert_true(@openrpc.validate_closed(document).document() is None)
  let ext = @reference.Resource::new(
    uri("https://ext.test/methods.json"),
    exact(external_methods),
    schema_roots=[
      @reference.JsonPointer::parse("/s").unwrap(),
      @reference.JsonPointer::parse("/p/schema").unwrap(),
    ],
  ).unwrap()
  let resources = @reference.ResourceSet::new([ext]).unwrap()
  let closed = @openrpc.validate_closed(document, resources~)
  assert_eq(reference_errors(closed.report()), [])
  assert_eq(closed.report().references(), @openrpc.Passed)
  assert_true(closed.document() is Some(_))
  let relative = doc("\"methods\":[{\"$ref\":\"methods.json#/m\"}]")
  assert_eq(
    @openrpc.validate(relative, resources~).references(),
    @openrpc.Incomplete,
  )
  let based = @openrpc.validate(
    relative,
    resources~,
    base=Some(uri("https://ext.test/api.json")),
  )
  assert_eq(based.references(), @openrpc.Passed)
  let broken = @reference.Resource::new(
    uri("https://ext.test/methods.json"),
    exact(
      external_methods.replace(old="\"type\":\"integer\"", new="\"type\":17"),
    ),
  ).unwrap()
  let failed = @openrpc.validate(
    document,
    resources=@reference.ResourceSet::new([broken]).unwrap(),
  )
  assert_eq(failed.schemas(), @openrpc.Failed)
}

///|
test "document schema identifiers use the document base" {
  let document = doc(
    "\"methods\":[],\"components\":{\"schemas\":{\"S\":{\"$id\":\"s.json\",\"definitions\":{\"x\":true},\"properties\":{\"a\":{\"$ref\":\"#/definitions/x\"}}}}}",
  )
  assert_eq(@openrpc.validate(document).references(), @openrpc.Passed)
  let leaving = doc(
    "\"methods\":[],\"components\":{\"schemas\":{\"S\":{\"$id\":\"s.json\",\"properties\":{\"a\":{\"$ref\":\"other.json\"}}}}}",
  )
  assert_eq(@openrpc.validate(leaving).references(), @openrpc.Incomplete)
  let based = @openrpc.validate(
    document,
    base=Some(uri("https://doc.test/api.json")),
  )
  assert_eq(based.references(), @openrpc.Passed)
  assert_eq(based.schemas(), @openrpc.Passed)
}

///|
test "documents declare their schema roots as resources" {
  let document = doc(
    "\"methods\":[{\"name\":\"op\",\"params\":[{\"name\":\"a\",\"schema\":true},{\"$ref\":\"#/components/contentDescriptors/P\"}],\"result\":{\"name\":\"r\",\"schema\":{}}}],\"components\":{\"schemas\":{\"S\":true},\"contentDescriptors\":{\"P\":{\"name\":\"p\",\"schema\":false}}}",
  )
  let resource = document.as_resource(uri("https://doc.test/api.json")).unwrap()
  assert_eq(resource.schema_roots().map(p => p.to_string()), [
    "/methods/0/params/0/schema", "/methods/0/result/schema", "/components/schemas/S",
    "/components/contentDescriptors/P/schema",
  ])
  let resources = @reference.ResourceSet::new([resource]).unwrap()
  let report = @openrpc.validate(
    document,
    resources~,
    base=Some(uri("https://doc.test/api.json")),
  )
  assert_eq(report.references(), @openrpc.Passed)
  assert_false(
    report
    .findings()
    .any(f => f.diagnostic().code() == @exact.ConflictingIdentifier),
  )
}

///|
test "server templates, external examples and literal refs are never resolved" {
  let document = doc(
    "\"servers\":[{\"url\":\"file:///{path}\",\"variables\":{\"path\":{\"default\":\"etc/passwd\"}}}],\"methods\":[{\"name\":\"op\",\"params\":[],\"x-ext\":{\"$ref\":\"https://evil.invalid/ext\"},\"examples\":[{\"name\":\"e\",\"params\":[{\"name\":\"a\",\"externalValue\":\"javascript:alert(1)\"}],\"result\":{\"name\":\"r\",\"value\":{\"$ref\":\"#/missing\"}}}]}]",
  )
  let report = @openrpc.validate(document)
  assert_eq(report.references(), @openrpc.Passed)
  assert_false(report.findings().any(f => f.phase() == @openrpc.References))
}
