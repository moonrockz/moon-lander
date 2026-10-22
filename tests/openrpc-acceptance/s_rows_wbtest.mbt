// Library evidence for compatibility.md rows S01-S18. Rows whose evidence is
// a dependency audit or an isolated consumer are covered by check:openrpc and
// qualify:openrpc and are recorded in qualification.md.

///|
fn document(body : String, version~ : String = "1.3.2") -> @openrpc.Document {
  @openrpc.read(
    "{\"openrpc\":\"" +
    version +
    "\",\"info\":{\"title\":\"API\",\"version\":\"2026-10-21\"}," +
    body +
    "}",
  )
  .document()
  .unwrap()
}

///|
fn written(document : @openrpc.Document) -> String {
  @openrpc.write(document).unwrap()
}

///|
test "S01 1.3.2 documents keep their own version and draft-07 schemas" {
  let d = document("\"methods\":[]")
  assert_eq(d.version().to_string(), "1.3.2")
  assert_eq(d.info().version(), "2026-10-21")
  assert_true(written(d).contains("\"openrpc\":\"1.3.2\""))
  assert_true(written(d).contains("\"version\":\"2026-10-21\""))
  let schema = @schema.Schema::from_json(
    @exact.parse("{\"type\":\"string\"}").unwrap().lower().unwrap(),
  ).unwrap()
  assert_true(schema.kind() is @schema.ObjectSchema(_))
}

///|
test "S02 exact values cross the core Json boundary explicitly" {
  let value = @exact.parse("{\"n\":9007199254740993,\"d\":0.10000000000000000001}")
    .unwrap()
    .lower()
    .unwrap()
  let core = @exact.to_core_json(value).unwrap()
  guard core is Object(fields) && fields.get("n") is Some(Number(_, repr~)) else {
    fail("expected an object with n")
  }
  assert_eq(repr, Some("9007199254740993"))
  let back = @exact.from_core_json(core).unwrap()
  assert_eq(@exact.write(back).unwrap(), @exact.write(value).unwrap())
}

///|
test "S03 parameter structures and descriptor order are retained" {
  for structure in ["by-name", "by-position", "either"] {
    let d = document(
      "\"methods\":[{\"name\":\"m\",\"paramStructure\":\"" +
      structure +
      "\",\"params\":[{\"name\":\"z\",\"schema\":true},{\"name\":\"a\",\"schema\":true}]}]",
    )
    let text = written(d)
    assert_true(text.contains("\"paramStructure\":\"" + structure + "\""))
    assert_true(
      text.contains("\"params\":[{\"name\":\"z\",\"schema\":true},{\"name\":\"a\""),
    )
  }
}

///|
test "S04 optional interior parameters keep required false with profile results" {
  let d = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[{\"name\":\"o\",\"required\":false,\"schema\":true},{\"name\":\"r\",\"required\":true,\"schema\":true}]}]",
  )
  assert_true(@openrpc.validate_closed(d).document() is None)
  let compatible = @openrpc.validate_closed(
    d,
    profile=@openrpc.MetaschemaCompatibility,
  )
  assert_true(compatible.document() is Some(_))
  assert_true(written(d).contains("{\"name\":\"o\",\"required\":false"))
}

///|
test "S05 results distinguish absent, null, empty object and structures" {
  let d = document(
    "\"methods\":[{\"name\":\"n\",\"params\":[]},{\"name\":\"z\",\"params\":[],\"result\":{\"name\":\"r\",\"schema\":{\"type\":\"null\"}}},{\"name\":\"e\",\"params\":[],\"result\":{\"name\":\"r\",\"schema\":{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}}},{\"name\":\"s\",\"params\":[],\"result\":{\"name\":\"r\",\"schema\":{\"type\":\"integer\"}}}]",
  )
  let results = d
    .methods()
    .map(m => {
      guard m is @openrpc.Inline(m) else { abort("inline") }
      m.result() is Some(_)
    })
  assert_eq(results, [false, true, true, true])
  assert_true(@openrpc.validate_closed(d).document() is Some(_))
}

///|
test "S06 component and recursive schema references close, missing and wrong kinds fail" {
  let good = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[{\"$ref\":\"#/components/contentDescriptors/P\"}]}],\"components\":{\"contentDescriptors\":{\"P\":{\"name\":\"p\",\"schema\":{\"$ref\":\"#/components/schemas/Tree\"}}},\"schemas\":{\"Tree\":{\"type\":\"object\",\"properties\":{\"kids\":{\"type\":\"array\",\"items\":{\"$ref\":\"#/components/schemas/Tree\"}},\"leaf\":true,\"never\":false}}}}",
  )
  assert_eq(@openrpc.validate(good).references(), @openrpc.Passed)
  let missing = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[{\"$ref\":\"#/components/contentDescriptors/Q\"}]}]",
  )
  assert_eq(@openrpc.validate(missing).references(), @openrpc.Failed)
  let wrong = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[{\"$ref\":\"#/components/errors/E\"}]}],\"components\":{\"errors\":{\"E\":{\"code\":1,\"message\":\"x\"}}}",
  )
  assert_true(
    @openrpc.validate(wrong)
    .findings()
    .any(f => f.diagnostic().code() == @exact.WrongType),
  )
}

///|
test "S07 exact numbers survive and no defaults are inserted" {
  let d = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[],\"result\":{\"name\":\"r\",\"schema\":{\"maximum\":12345678901234567890123,\"multipleOf\":0.1,\"minimum\":1e-400}}}]",
  )
  let text = written(d)
  assert_true(text.contains("12345678901234567890123"))
  assert_true(text.contains("0.1"))
  assert_true(text.contains("1e-400"))
  assert_false(text.contains("\"deprecated\""))
  assert_false(text.contains("\"required\""))
  assert_false(text.contains("paramStructure"))
}

///|
test "S08 titles, summaries, descriptions and deprecation survive" {
  let d = document(
    "\"methods\":[{\"name\":\"m\",\"summary\":\"S\",\"description\":\"D\",\"deprecated\":true,\"params\":[{\"name\":\"p\",\"summary\":\"PS\",\"description\":\"PD\",\"deprecated\":false,\"schema\":{\"title\":\"T\",\"description\":\"SD\",\"format\":\"date-time\"}}]}]",
  )
  let text = written(d)
  for
    part in [
      "\"summary\":\"S\"", "\"description\":\"D\"", "\"deprecated\":true", "\"summary\":\"PS\"",
      "\"deprecated\":false", "\"title\":\"T\"", "\"format\":\"date-time\"",
    ] {
    assert_true(text.contains(part), msg=part)
  }
}

///|
test "S09 extensions keep null, nested values and literal references" {
  let d = document(
    "\"x-smithy-protocol\":null,\"methods\":[{\"name\":\"m\",\"params\":[],\"x-smithy-error-data\":{\"$ref\":\"#/not/followed\"},\"x-smithy-error-examples\":[{\"a\":[1,{\"b\":null}]}],\"examples\":[{\"name\":\"e\",\"params\":[],\"x-smithy-param-structure\":\"by-name\"}]}]",
  )
  let text = written(d)
  for
    part in [
      "\"x-smithy-protocol\":null", "\"x-smithy-error-data\":{\"$ref\":\"#/not/followed\"}",
      "\"x-smithy-error-examples\":[{\"a\":[1,{\"b\":null}]}]", "\"x-smithy-param-structure\":\"by-name\"",
    ] {
    assert_true(text.contains(part), msg=part)
  }
  assert_eq(@openrpc.validate(d).references(), @openrpc.Passed)
}

///|
test "S10 error data is instance data and extension schemas are checked explicitly" {
  let d = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[],\"errors\":[{\"code\":1,\"message\":\"x\",\"data\":{\"$ref\":\"#/missing\",\"type\":17}}],\"x-error-schema\":{\"type\":17}}]",
  )
  assert_true(@openrpc.validate_closed(d).document() is Some(_))
  let root = d.to_json()
  let schema = root
    .get("methods")
    .unwrap()
    .array_item(0)
    .unwrap()
    .get("x-error-schema")
    .unwrap()
  let report = @schema.validate_json(schema, root~, path=[
    "methods", "0", "x-error-schema",
  ])
  assert_eq(report.diagnostics()[0].path(), [
    "methods", "0", "x-error-schema", "type",
  ])
}

///|
test "S12 pairings keep results and add no standard error field in 1.3.2" {
  let d = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[],\"result\":{\"name\":\"r\",\"schema\":true},\"examples\":[{\"name\":\"ok\",\"params\":[{\"name\":\"a\",\"value\":1}],\"result\":{\"name\":\"r\",\"value\":2}}],\"x-smithy-error-examples\":[{\"name\":\"bad\",\"error\":{\"code\":1}}]}]",
  )
  let text = written(d)
  assert_true(
    text.contains("\"result\":{\"name\":\"r\",\"value\":2}"),
    msg=text,
  )
  assert_false(text.contains("\"examples\":[{\"error\""))
  assert_true(text.contains("\"x-smithy-error-examples\""))
}

///|
test "S13 processing is deterministic and fetches nothing" {
  let d = document(
    "\"servers\":[{\"name\":\"s\",\"url\":\"file:///{p}\",\"variables\":{\"p\":{\"default\":\"etc/passwd\"}}}],\"methods\":[{\"$ref\":\"https://evil.invalid/m.json#/m\"}]",
  )
  let first = @openrpc.validate(d).findings().map(f => f.to_repr().to_string())
  let second = @openrpc.validate(d).findings().map(f => f.to_repr().to_string())
  assert_eq(first, second)
  assert_eq(written(d), written(d))
  assert_eq(@openrpc.validate(d).references(), @openrpc.Incomplete)
}

///|
test "S16 document validation makes no runtime exchange claims" {
  let d = document(
    "\"methods\":[{\"name\":\"m\",\"params\":[{\"name\":\"a\",\"schema\":{\"type\":\"string\"}}],\"result\":{\"name\":\"r\",\"schema\":{\"type\":\"null\"}},\"examples\":[{\"name\":\"e\",\"params\":[{\"name\":\"a\",\"value\":42}],\"result\":{\"name\":\"r\",\"value\":\"not null\"}}]}]",
  )
  let result = @openrpc.validate_closed(d)
  assert_true(result.document() is Some(_))
  assert_true(result.report().findings().is_empty())
}
