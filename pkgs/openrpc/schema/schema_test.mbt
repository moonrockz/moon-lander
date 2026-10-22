///|
fn value(source : String) -> @json.Value {
  @json.parse(source).unwrap().lower().unwrap()
}

///|
test "reference target diagnostics use root paths instead of the schema site" {
  let root = value(
    "{\"components\":{\"schemas\":{\"S\":{\"properties\":{\"bad\":17}}}}}",
  )
  let schema = @schema.Schema::from_json(
    value("{\"$ref\":\"#/components/schemas/S\"}"),
  ).unwrap()
  let report = @schema.validate(schema, root~, path=[
    "methods", "0", "result", "schema",
  ])
  assert_eq(report.diagnostics().length(), 1)
  assert_eq(report.diagnostics()[0].path(), [
    "components", "schemas", "S", "properties", "bad",
  ])
  let report = @schema.validate_json(value("{\"type\":17}"), root~, path=[
    "methods", "0", "result", "schema",
  ])
  assert_eq(report.diagnostics()[0].path(), [
    "methods", "0", "result", "schema", "type",
  ])
}

///|
test "boolean schemas and exact retention are independent" {
  for
    source in [
      "true", "false", "{\"type\":\"integer\",\"minimum\":9007199254740993}",
    ] {
    let raw = value(source)
    let schema = @schema.Schema::from_json(raw).unwrap()
    assert_eq(@json.write(schema.to_json()).unwrap(), @json.write(raw).unwrap())
    let report = @schema.validate(schema, root=raw)
    assert_true(report.is_complete())
    assert_eq(report.diagnostics().length(), 0)
  }
  assert_true(@schema.Schema::from_json(value("null")) is Err(_))
  assert_true(@schema.Schema::from_json(value("[]")) is Err(_))
}

///|
test "recursive local schema graph resolves without expansion" {
  let root = value(
    "{\"components\":{\"schemas\":{\"Node\":{\"type\":\"object\",\"properties\":{\"next\":{\"$ref\":\"#/components/schemas/Node\"}}}}}}",
  )
  let start = value("{\"$ref\":\"#/components/schemas/Node\"}")
  let report = @schema.validate(
    @schema.Schema::from_json(start).unwrap(),
    root~,
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
}

///|
test "schema references reject missing and wrong targets" {
  for
    (source, code) in [
      ("{\"$ref\":\"#/missing\"}", @json.UnresolvedReference),
      ("{\"$ref\":\"#/value\"}", @json.WrongType),
      ("{\"$ref\":\"#/~2\"}", @json.InvalidReference),
    ] {
    let root = value("{\"value\":17}")
    let report = @schema.validate_json(value(source), root~)
    assert_true(report.diagnostics().iter().any(d => d.code() == code))
  }
}

///|
test "literal references are data and ref siblings are retained but ignored" {
  let raw = value(
    "{\"default\":{\"$ref\":\"#/missing\"},\"examples\":[{\"$ref\":\"#/missing\"}],\"enum\":[{\"$ref\":\"#/missing\"}],\"const\":{\"$ref\":\"#/missing\"}}",
  )
  let report = @schema.validate(
    @schema.Schema::from_json(raw).unwrap(),
    root=raw,
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
  let sibling = value("{\"$ref\":\"#/ok\",\"type\":17,\"properties\":false}")
  let report = @schema.validate(
    @schema.Schema::from_json(sibling).unwrap(),
    root=value("{\"ok\":true}"),
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
}

///|
test "schema keyword shapes use exact integer semantics" {
  for
    source in [
      "{\"type\":\"nope\"}", "{\"type\":[\"string\",\"string\"]}", "{\"properties\":false}",
      "{\"items\":3}", "{\"required\":[\"a\",\"a\"]}", "{\"additionalProperties\":null}",
      "{\"maxItems\":1.5}", "{\"minLength\":-1}", "{\"multipleOf\":0}", "{\"minimum\":\"1\"}",
    ] {
    let raw = value(source)
    let report = @schema.validate_json(raw, root=raw)
    assert_true(
      report.diagnostics().iter().any(d => d.code() == @json.InvalidSchema),
      msg=source,
    )
  }
  let raw = value(
    "{\"maxItems\":1e400,\"minLength\":-0,\"required\":[],\"items\":false,\"additionalProperties\":true}",
  )
  let report = @schema.validate(
    @schema.Schema::from_json(raw).unwrap(),
    root=raw,
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
}

///|
test "unsupported dialect checks and limits cannot claim complete coverage" {
  for
    (source, code) in [
      (
        "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\"}",
        @json.UnsupportedDialect,
      ),
      ("{\"$ref\":\"other.json#/x\"}", @json.MissingBaseUri),
    ] {
    let raw = value(source)
    let report = @schema.validate(
      @schema.Schema::from_json(raw).unwrap(),
      root=raw,
    )
    assert_false(report.is_complete())
    assert_true(
      report.diagnostics().iter().any(d => d.code() == code),
      msg=source,
    )
  }
  for
    dialect in [
      "http://json-schema.org/draft-07/schema", "http://json-schema.org/draft-07/schema#",
      "https://json-schema.org/draft-07/schema", "https://json-schema.org/draft-07/schema#",
    ] {
    let raw = @json.Value::object([("$schema", @json.Value::string(dialect))]).unwrap()
    assert_true(
      @schema.validate(@schema.Schema::from_json(raw).unwrap(), root=raw).is_complete(),
    )
  }
  let raw = value("{\"properties\":{\"a\":{},\"b\":{}}}")
  let report = @schema.validate(
    @schema.Schema::from_json(raw).unwrap(),
    root=raw,
    max_nodes=1,
  )
  assert_false(report.is_complete())
  assert_true(
    report.diagnostics().iter().any(d => d.code() == @json.LimitExceeded),
  )
}

///|
test "reference limits and finding truncation stay incomplete" {
  let raw = value("{\"$ref\":\"#\"}")
  let report = @schema.validate(
    @schema.Schema::from_json(raw).unwrap(),
    root=raw,
    max_edges=0,
  )
  assert_false(report.is_complete())
  assert_true(
    report.diagnostics().iter().any(d => d.code() == @json.LimitExceeded),
  )
  let raw = value("{\"type\":42,\"required\":false,\"minimum\":null}")
  let report = @schema.validate_json(raw, root=raw, max_findings=1)
  assert_false(report.is_complete())
  assert_eq(report.diagnostics().length(), 1)
  assert_eq(report.diagnostics()[0].code(), @json.LimitExceeded)
}

///|
test "declared dialect applies before reference sibling rules" {
  let raw = value(
    "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"$ref\":\"#/ok\"}",
  )
  let report = @schema.validate(
    @schema.Schema::from_json(raw).unwrap(),
    root=value("{\"ok\":true}"),
  )
  assert_false(report.is_complete())
  assert_true(
    report.diagnostics().iter().any(d => d.code() == @json.UnsupportedDialect),
  )
}
