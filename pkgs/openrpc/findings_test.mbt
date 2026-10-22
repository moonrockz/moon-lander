
///|
test "findings are ordered by resource, pointer tokens, code and occurrence" {
  let methods = []
  for i in 0..<11 {
    let params = if i == 2 || i == 10 {
      "[{\"name\":\"p\",\"schema\":true},{\"name\":\"p\",\"schema\":true}]"
    } else {
      "[]"
    }
    methods.push("{\"name\":\"m\{i}\",\"params\":\{params}}")
  }
  let document = doc(
    "\"methods\":[" +
    methods.join(",") +
    "],\"components\":{\"schemas\":{\"S\":{\"pattern\":\"(\"}}}",
  )
  let errors = @openrpc.validate(document)
    .findings()
    .filter(f => f.severity() == @openrpc.Error)
    .map(f => f.location().path())
  assert_eq(errors, [
    ["components", "schemas", "S", "pattern"],
    ["methods", "2", "params", "1", "name"],
    ["methods", "10", "params", "1", "name"],
  ])
}

///|
let located_source : String = "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"😀\",\"version\":\"1\"},\n\"methods\":[{\"name\":\"a\",\"params\":[]},{\"name\":\"a\",\"params\":[]}]}"

///|
test "source map spans locate input findings in UTF-16 units" {
  let read = @openrpc.read(located_source, source_id=Some("api.json"))
  let source_map = read.source_map().unwrap()
  let report = @openrpc.validate(
    read.document().unwrap(),
    source_map=Some(source_map),
  )
  let duplicate = report
    .findings()
    .filter(f => f.phase() == @openrpc.Normative)[0]
  let location = duplicate.location()
  assert_eq(location.path(), ["methods", "1", "name"])
  assert_eq(location.span().map(s => (s.start(), s.end())), Some((100, 103)))
  assert_eq(location.source_id(), Some("api.json"))
  let position = source_map.position(100).unwrap()
  assert_eq((position.line(), position.column()), (2, 45))
  assert_eq(duplicate.related().map(r => r.path()), [["methods", "0", "name"]])
  assert_eq(duplicate.version().to_string(), "1.3.2")
  assert_eq(duplicate.profile(), @openrpc.Specification)
  assert_eq(report.version().to_string(), "1.3.2")
}

///|
test "generated documents have no source locations" {
  let method_ = @openrpc.Method::new(
    @openrpc.MethodName::parse("a").unwrap(),
    [],
  ).unwrap()
  let document = @openrpc.Document::new(
    @openrpc.DocumentVersion::parse("1.4.0").unwrap(),
    @openrpc.Info::new("T", "1").unwrap(),
    [@openrpc.Inline(method_), @openrpc.Inline(method_)],
  ).unwrap()
  let report = @openrpc.validate(document)
  assert_true(report.findings().length() > 0)
  assert_true(report.findings().all(f => f.location().span() is None))
}

///|
test "external findings keep their resource and take no input spans" {
  let broken = external_methods.replace(
    old="\"type\":\"integer\"",
    new="\"type\":17",
  )
  let a = @reference.Resource::new(
    uri("https://a.test/m.json"),
    exact(broken),
    schema_roots=[@reference.JsonPointer::parse("/s").unwrap()],
  ).unwrap()
  let b = @reference.Resource::new(
    uri("https://b.test/m.json"),
    exact(broken),
    schema_roots=[@reference.JsonPointer::parse("/s").unwrap()],
  ).unwrap()
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"$ref\":\"https://a.test/m.json#/m\"},{\"$ref\":\"https://b.test/m.json#/m\"}]}"
  let read = @openrpc.read(source)
  let report = @openrpc.validate(
    read.document().unwrap(),
    resources=@reference.ResourceSet::new([a, b]).unwrap(),
    source_map=read.source_map(),
  )
  let schema_errors = report
    .findings()
    .filter(f => f.phase() == @openrpc.SchemaDocument)
  assert_eq(
    schema_errors.map(f => {
      (f.location().resource().map(u => u.text()), f.location().path())
    }),
    [
      (Some("https://a.test/m.json"), ["s", "type"]),
      (Some("https://b.test/m.json"), ["s", "type"]),
    ],
  )
  assert_true(schema_errors.all(f => f.location().span() is None))
  let duplicate = report
    .findings()
    .filter(f => f.phase() == @openrpc.Normative)[0]
  assert_eq(
    duplicate.location().resource().map(u => u.text()),
    Some("https://b.test/m.json"),
  )
  assert_eq(duplicate.location().path(), ["m", "name"])
  assert_eq(duplicate.location().span(), None)
  assert_eq(duplicate.chain().map(c => c.path()), [["methods", "1", "$ref"]])
  assert_true(duplicate.chain()[0].span() is Some(_))
}

///|
test "broken pointer findings point at the reference site" {
  let document = doc(
    "\"methods\":[],\"components\":{\"schemas\":{\"S\":{\"$ref\":\"#/components/schemas/Missing/deep\"}}}",
  )
  let broken = @openrpc.validate(document)
    .findings()
    .filter(f => f.phase() == @openrpc.References)
  assert_eq(broken.length(), 1)
  assert_eq(broken[0].diagnostic().code(), @exact.UnresolvedReference)
  assert_eq(broken[0].location().path(), [
    "components", "schemas", "S", "$ref",
  ])
  let methods = doc(
    "\"methods\":[{\"$ref\":\"#/components/missing/m\"}]",
  )
  let unresolved = @openrpc.validate(methods)
    .findings()
    .filter(f => f.phase() == @openrpc.References)
  assert_eq(unresolved.map(f => f.location().path()), [["methods", "0", "$ref"]])
}

///|
test "finding limits truncate and leave the affected facets incomplete" {
  let document = doc(
    "\"methods\":[{\"name\":\"a\",\"params\":[]},{\"name\":\"a\",\"params\":[{\"$ref\":\"#/missing\"}]}],\"components\":{\"schemas\":{\"S\":{\"pattern\":\"(\"}}}",
  )
  let limits = @exact.Limits::new(max_findings=1)
  let report = @openrpc.validate(document, limits~)
  let kept = report
    .findings()
    .filter(f => f.diagnostic().code() != @exact.LimitExceeded)
  assert_eq(kept.length(), 1)
  let markers = report
    .findings()
    .filter(f => f.diagnostic().code() == @exact.LimitExceeded)
  assert_true(markers.all(f => f.severity() == @openrpc.Information))
  for
    (phase, coverage) in [
      (@openrpc.SchemaDocument, report.schemas()),
      (@openrpc.Normative, report.normative()),
      (@openrpc.References, report.references()),
    ] {
    assert_true(coverage != @openrpc.Passed, msg=phase.to_repr().to_string())
    if coverage == @openrpc.Incomplete {
      assert_true(markers.any(f => f.phase() == phase))
    }
  }
  assert_true(@openrpc.validate_closed(document, limits~).document() is None)
}

///|
test "a truncated reference index is reported as a limit" {
  let document = doc(
    "\"methods\":[],\"components\":{\"schemas\":{\"A\":{\"$id\":\"https://x.test/s.json\"},\"B\":{\"$id\":\"https://x.test/s.json\"},\"C\":{\"$id\":\"https://x.test/s.json\"}}}",
  )
  let report = @openrpc.validate(
    document,
    limits=@exact.Limits::new(max_findings=1),
  )
  assert_true(
    report
    .findings()
    .any(f => {
      f.phase() == @openrpc.References &&
      f.diagnostic().code() == @exact.LimitExceeded
    }),
  )
}
