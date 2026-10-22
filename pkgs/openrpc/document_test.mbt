///|
test "document reader retains independent versions exact extensions and source" {
  for version in ["1.3.2", "1.4.0", "1.4.12"] {
    let source = " \n{\"openrpc\":\"" +
      version +
      "\",\"info\":{\"title\":\"API\",\"version\":\"2026\"},\"methods\":[],\"x-vendor\":9007199254740993}\r\n"
    let read = @openrpc.read(source)
    assert_true(read.diagnostics().is_empty())
    let doc = read.document().unwrap()
    assert_eq(doc.version().to_string(), version)
    assert_eq(doc.info().version(), "2026")
    assert_eq(read.cst().unwrap().reproduce(), source)
    let output = @openrpc.write(doc).unwrap()
    assert_true(output.contains("9007199254740993"))
    assert_eq(
      @openrpc.write(@openrpc.read(output).document().unwrap()).unwrap(),
      output,
    )
  }
}

///|
test "unsupported versions retain syntax and return structured path" {
  let source = "{\"openrpc\":\"2.0.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[]}"
  let read = @openrpc.read(source)
  assert_true(read.document() is None)
  assert_eq(read.cst().unwrap().reproduce(), source)
  assert_eq(read.diagnostics()[0].code(), @exact.UnsupportedVersion)
  assert_eq(read.diagnostics()[0].path(), ["openrpc"])
  assert_true(read.diagnostics()[0].span() is Some(_))
}

///|
test "descriptor order and successful null result survive writing" {
  let source = "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"paramStructure\":\"by-position\",\"params\":[{\"name\":\"optional\",\"required\":false,\"schema\":true},{\"name\":\"required\",\"required\":true,\"schema\":true}],\"result\":{\"name\":\"result\",\"schema\":{\"type\":\"null\"}}}]}"
  let read = @openrpc.read(source)
  let document = read.document().unwrap()
  let report = @openrpc.validate(document)
  assert_true(
    report
    .findings()
    .iter()
    .any(f => {
      f.diagnostic().code() == @exact.ParameterOrder &&
      f.severity() == @openrpc.Error
    }),
  )
  let compatible = @openrpc.validate(
    document,
    profile=@openrpc.MetaschemaCompatibility,
  )
  assert_true(
    compatible
    .findings()
    .iter()
    .any(f => {
      f.diagnostic().code() == @exact.ParameterOrder &&
      f.severity() == @openrpc.Warning
    }),
  )
  let output = @openrpc.write(document).unwrap()
  assert_true(output.contains("\"name\":\"optional\""))
  assert_true(output.contains("\"type\":\"null\""))
}

///|
test "recursive local component schemas resolve without treating example data as a reference" {
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":{\"$ref\":\"#/components/schemas/Node\"}}}],\"components\":{\"schemas\":{\"Node\":{\"type\":\"object\",\"properties\":{\"next\":{\"$ref\":\"#/components/schemas/Node\"}},\"default\":{\"$ref\":\"https://example.invalid/literal\"}}}}}"
  let document = @openrpc.read(source).document().unwrap()
  let report = @openrpc.validate(document)
  assert_false(
    report
    .findings()
    .iter()
    .any(f => f.diagnostic().code() == @exact.UnresolvedReference),
  )
  assert_eq(report.references(), @openrpc.Passed)
}

///|
test "incomplete validation cannot produce a closed wrapper" {
  let source = "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\"servers\":[{\"url\":\"https://example.invalid\"}]}"
  let doc = @openrpc.read(source).document().unwrap()
  assert_true(@openrpc.validate_closed(doc).document() is None)
}

///|
test "draft seven references ignore a sibling identifier scope" {
  let source = "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\"components\":{\"schemas\":{\"R\":{\"$id\":\"other.json\",\"$ref\":\"#/components/schemas/S\"},\"S\":true}}}"
  let result = @openrpc.validate_closed(
    @openrpc.read(source).document().unwrap(),
  )
  assert_eq(result.report().schemas(), @openrpc.Passed)
  assert_true(result.document() is Some(_))
}

///|
test "component keys are read as written and checked by version" {
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\"components\":{\"schemas\":{\"bad key!\":true}}}"
  let document = @openrpc.read(source).document().unwrap()
  let key = document.components().unwrap().schemas().unwrap()[0].0
  assert_eq(key.to_string(), "bad key!")
  assert_false(key.is_conforming())
  assert_true(@openrpc.write(document).unwrap().contains("\"bad key!\":true"))
  let old = @openrpc.read(source.replace(old="1.4.0", new="1.3.2"))
    .document()
    .unwrap()
  assert_eq(@openrpc.validate(old).normative(), @openrpc.Failed)
}

///|
test "schema structural failures retain the complete document path and span" {
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":{\"properties\":{\"x\":{\"type\":17}}}}}]}"
  let result = @openrpc.read(source)
  assert_true(result.document() is None)
  let d = result.diagnostics()[0]
  assert_eq(d.path(), [
    "methods", "0", "result", "schema", "properties", "x", "type",
  ])
  let span = d.span().unwrap()
  assert_eq(source[span.start():span.end()].to_owned(), "17")
}

///|
test "reader carries explicit parser bounds into schema decoding" {
  let schema = "{\"items\":".repeat(400) + "true" + "}".repeat(400)
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":" +
    schema +
    "}}]}"
  let limits = @exact.Limits::new(max_depth=500)
  let result = @openrpc.read(source, limits~)
  assert_true(result.document() is Some(_))
  assert_eq(result.cst().unwrap().reproduce(), source)
}

///|
test "unavailable external schema resources leave reference coverage incomplete" {
  for ref_ in ["https://schemas.example/s.json#/definitions/a", "relative.json"] {
    let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":{\"$ref\":\"" +
      ref_ +
      "\"}}}]}"
    let document = @openrpc.read(source).document().unwrap()
    let report = @openrpc.validate(document)
    assert_eq(report.references(), @openrpc.Incomplete, msg=ref_)
    assert_eq(report.schemas(), @openrpc.Passed, msg=ref_)
    assert_true(@openrpc.validate_closed(document).document() is None, msg=ref_)
  }
}
