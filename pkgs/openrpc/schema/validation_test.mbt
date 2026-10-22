///|
fn checked_report(source : String) -> @schema.Report {
  let raw = @json.parse(source).unwrap().lower().unwrap()
  @schema.validate_json(raw, root=raw)
}

///|
test "all schema containers are checked and unknown keyword values stay opaque" {
  let report = checked_report(
    "{\"properties\":{\"x\":false},\"definitions\":{\"x\":true},\"patternProperties\":{},\"dependencies\":{\"a\":[\"b\"],\"c\":false},\"propertyNames\":true,\"contains\":false,\"if\":{},\"then\":false,\"else\":true,\"not\":{},\"allOf\":[true],\"anyOf\":[false],\"oneOf\":[{}],\"unknown\":{\"$ref\":\"missing.json\",\"type\":17},\"x-schema\":{\"type\":17}}",
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
  for
    source in [
      "{\"patternProperties\":{\"a\":17}}", "{\"dependencies\":{\"a\":[\"b\",\"b\"]}}",
      "{\"dependencies\":{\"a\":[17]}}", "{\"dependencies\":{\"a\":17}}", "{\"contains\":17}",
      "{\"propertyNames\":17}", "{\"if\":17}", "{\"then\":17}", "{\"else\":17}",
      "{\"not\":17}", "{\"allOf\":[]}", "{\"anyOf\":[true,17]}", "{\"oneOf\":false}",
    ] {
    let report = checked_report(source)
    assert_true(report.is_complete(), msg=source)
    assert_true(
      report.diagnostics().any(d => d.code() == @json.InvalidSchema),
      msg=source,
    )
  }
}

///|
test "enum uniqueness uses exact mathematical JSON equality" {
  for
    source in [
      "{\"enum\":[1,1.00]}", "{\"enum\":[-0,0e999999999999999999]}", "{\"enum\":[{\"a\":[1,2],\"b\":false},{\"b\":false,\"a\":[1.0,2e0]}]}",
    ] {
    let report = checked_report(source)
    assert_true(report.is_complete(), msg=source)
    assert_eq(report.diagnostics().length(), 1, msg=source)
    assert_eq(report.diagnostics()[0].code(), @json.InvalidSchema)
    assert_eq(report.diagnostics()[0].path(), ["enum", "1"])
  }
  for
    source in [
      "{\"enum\":[9007199254740992,9007199254740993]}", "{\"enum\":[1,\"1\",true,null,{},[]]}",
      "{\"enum\":[{\"$ref\":\"missing.json\"},{\"type\":17}]}",
    ] {
    let report = checked_report(source)
    assert_true(report.is_complete(), msg=source)
    assert_eq(report.diagnostics().length(), 0, msg=source)
  }
}

///|
test "structural schema reporting reserves work before shared graph expansion" {
  let mut raw = @json.Value::object([]).unwrap()
  for _ in 0..<20 {
    raw = @json.Value::object([("allOf", @json.Value::array([raw, raw]))]).unwrap()
  }
  let report = @schema.validate_json(raw, root=raw, max_nodes=10)
  assert_false(report.is_complete())
  assert_true(report.diagnostics().any(d => d.code() == @json.LimitExceeded))
}

///|
test "enum comparisons have one aggregate work bound" {
  let raw = @json.parse("{\"enum\":[1,2,3]}").unwrap().lower().unwrap()
  let report = @schema.validate_json(raw, root=raw, max_comparison_work=1)
  assert_false(report.is_complete())
  assert_true(report.diagnostics().any(d => d.code() == @json.LimitExceeded))
}

///|
test "schema validation inherits explicit exact value limits" {
  let raw = @json.parse("{\"default\":\"large literal\"}")
    .unwrap()
    .lower()
    .unwrap()
  let report = @schema.validate_json(
    raw,
    root=raw,
    limits=@json.Limits::new(max_source=8),
  )
  assert_false(report.is_complete())
  assert_eq(report.diagnostics()[0].code(), @json.LimitExceeded)
}

///|
test "schema pattern checks use the portable grammar and exact schema positions" {
  let report = checked_report(
    "{\"pattern\":\"(?<=a)b\",\"patternProperties\":{\"(?<word>x)\\\\k<word>\":true},\"default\":{\"pattern\":\"[\"},\"unknown\":{\"patternProperties\":{\"[\":17}}}",
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
  for
    (source, path) in [
      ("{\"pattern\":\"[\"}", ["pattern"]),
      ("{\"patternProperties\":{\"[\":true}}", ["patternProperties", "["]),
    ] {
    let report = checked_report(source)
    assert_true(report.is_complete())
    assert_eq(report.diagnostics().length(), 1)
    assert_eq(report.diagnostics()[0].code(), @json.InvalidSchema)
    assert_eq(report.diagnostics()[0].path(), path)
    assert_true(report.diagnostics()[0].span() is None)
  }
}

///|
test "extension schemas are submitted with explicit path root and retrieval base" {
  let root = @json.parse(
      "{\"x-payload\":{\"schema\":{\"$ref\":\"https://schemas.example/document#/definitions/S\"}},\"definitions\":{\"S\":{\"type\":17}}}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let raw = root.get("x-payload").unwrap().get("schema").unwrap()
  let base = @reference.UriReference::parse("https://schemas.example/document").unwrap()
  let report = @schema.validate_json(
    raw,
    root~,
    path=["x-payload", "schema"],
    base=Some(base),
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 1)
  assert_eq(report.diagnostics()[0].path(), ["definitions", "S", "type"])
  let without_base = @schema.validate_json(raw, root~, path=[
    "x-payload", "schema",
  ])
  assert_false(without_base.is_complete())
  assert_eq(without_base.diagnostics()[0].path(), [
    "x-payload", "schema", "$ref",
  ])
}

///|
test "schema base configuration cannot silently use relative or fragment bases" {
  let raw = @json.Value::boolean(true)
  for text in ["relative.json", "https://schemas.example/document#fragment"] {
    let report = @schema.validate_json(
      raw,
      root=raw,
      base=Some(@reference.UriReference::parse(text).unwrap()),
    )
    assert_false(report.is_complete())
    assert_eq(report.diagnostics()[0].code(), @json.InvalidReference)
  }
}

///|
test "schema finding limits use the stricter explicit and shared bounds" {
  let raw = @json.parse("{\"type\":17,\"required\":false}")
    .unwrap()
    .lower()
    .unwrap()
  let report = @schema.validate_json(
    raw,
    root=raw,
    limits=@json.Limits::new(max_findings=1),
  )
  assert_false(report.is_complete())
  assert_eq(report.diagnostics().length(), 1)
  assert_eq(report.diagnostics()[0].code(), @json.LimitExceeded)
}

///|
test "reference token exhaustion cannot report complete schema coverage" {
  let pointer = "#" + String::make(300, '/').replace(old="/", new="/x")
  let raw = @json.Value::object([("$ref", @json.Value::string(pointer))]).unwrap()
  let report = @schema.validate_json(raw, root=raw)
  assert_false(report.is_complete())
  assert_true(report.diagnostics().any(d => d.code() == @json.LimitExceeded))
}

///|
fn scoped(text : String) -> @json.Value {
  @json.parse(text).unwrap().lower().unwrap()
}

///|
test "nested identifiers change the scope of relative schema references" {
  let raw = scoped(
    "{\"$id\":\"http://x.test/root.json\",\"definitions\":{\"B\":{\"$id\":\"other.json\",\"definitions\":{\"X\":{\"type\":17},\"N\":{\"$id\":\"#named\",\"minLength\":-1}},\"properties\":{\"p\":{\"$ref\":\"#/definitions/X\"},\"q\":{\"$ref\":\"#named\"},\"r\":{\"$ref\":\"http://x.test/root.json#/definitions/B/definitions/X\"}}}}}",
  )
  let report = @schema.validate_json(raw, root=raw)
  assert_true(report.is_complete())
  let paths = report.diagnostics().map(d => d.path())
  assert_eq(paths, [
    ["definitions", "B", "definitions", "N", "minLength"],
    ["definitions", "B", "definitions", "X", "type"],
  ])
  assert_true(report.references_complete())
  assert_eq(report.resolutions().length(), 3)
}

///|
test "recursive schema graphs terminate without findings" {
  let raw = scoped(
    "{\"$id\":\"http://x.test/tree.json\",\"properties\":{\"child\":{\"$ref\":\"#\"},\"list\":{\"items\":{\"$ref\":\"tree.json\"}}}}",
  )
  let report = @schema.validate_json(raw, root=raw)
  assert_eq(report.diagnostics().map(d => (d.code(), d.path())), [])
  assert_true(report.is_complete())
}

///|
test "explicit external schema resources are validated when supplied" {
  let raw = scoped("{\"$ref\":\"https://ext.test/s.json#/definitions/a\"}")
  let missing = @schema.validate_json(raw, root=raw)
  assert_false(missing.is_complete())
  assert_false(missing.references_complete())
  assert_eq(missing.diagnostics()[0].code(), @json.UnavailableResource)
  let ext = @reference.Resource::new(
    @reference.UriReference::parse("https://ext.test/s.json").unwrap(),
    scoped(
      "{\"definitions\":{\"a\":{\"minLength\":-1,\"items\":{\"$ref\":\"#/definitions/a\"}}}}",
    ),
    schema_roots=[@reference.JsonPointer::parse("/definitions/a").unwrap()],
  ).unwrap()
  let resources = @reference.ResourceSet::new([ext]).unwrap()
  let found = @schema.validate_json(raw, root=raw, resources~)
  assert_true(found.is_complete())
  assert_eq(found.diagnostics().map(d => d.path()), [
    ["definitions", "a", "minLength"],
  ])
  let relative = scoped("{\"$ref\":\"s.json#/definitions/a\"}")
  let no_base = @schema.validate_json(relative, root=relative, resources~)
  assert_eq(no_base.diagnostics()[0].code(), @json.MissingBaseUri)
  let with_base = @schema.validate_json(
    relative,
    root=relative,
    resources~,
    base=Some(
      @reference.UriReference::parse("https://ext.test/input.json").unwrap(),
    ),
  )
  assert_true(with_base.is_complete())
}

///|
test "a submitted schema that differs from its root path keeps both checks" {
  let root = scoped("{\"definitions\":{\"S\":{\"type\":17}}}")
  let raw = scoped("{\"$ref\":\"#/definitions/S\",\"type\":18}")
  let report = @schema.validate_json(raw, root~, path=["definitions", "S"])
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().map(d => d.path()), [
    ["definitions", "S", "type"],
  ])
  let same = root.get("definitions").unwrap().get("S").unwrap()
  let physical = @schema.validate_json(same, root~, path=["definitions", "S"])
  assert_eq(physical.diagnostics().length(), 1)
}

///|
test "a registered base names the physical resource for the submitted schema" {
  let doc = scoped(
    "{\"definitions\":{\"S\":{\"$ref\":\"#/definitions/T\"},\"T\":{\"maxLength\":-1}}}",
  )
  let base = @reference.UriReference::parse("https://doc.test/a.json").unwrap()
  let resources = @reference.ResourceSet::new([
    @reference.Resource::new(base, doc).unwrap(),
  ]).unwrap()
  let raw = doc.get("definitions").unwrap().get("S").unwrap()
  let report = @schema.validate_json(
    raw,
    root=doc,
    path=["definitions", "S"],
    base=Some(base),
    resources~,
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().map(d => d.path()), [
    ["definitions", "T", "maxLength"],
  ])
}

///|
test "identifiers apply at referenced locations that were never declared roots" {
  let ext = @reference.Resource::new(
    @reference.UriReference::parse("https://ext.test/d.json").unwrap(),
    scoped(
      "{\"name\":\"a\",\"schema\":{\"$id\":\"https://ids.test/s.json\",\"definitions\":{\"x\":true},\"properties\":{\"p\":{\"$ref\":\"#/definitions/x\"}}}}",
    ),
  ).unwrap()
  let raw = scoped("{\"$ref\":\"https://ext.test/d.json#/schema\"}")
  let report = @schema.validate_json(
    raw,
    root=raw,
    resources=@reference.ResourceSet::new([ext]).unwrap(),
  )
  assert_eq(report.diagnostics().map(d => (d.code(), d.path())), [])
  assert_true(report.is_complete())
}
