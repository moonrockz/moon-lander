///|
fn draft07_value(text : String) -> @exact.Value {
  @exact.parse(text).unwrap().lower().unwrap()
}

///|
test "draft-07 subschema positions skip literals and non-schema forms" {
  let positions = fn(name, text) {
    @domain.draft07_subschemas(name, draft07_value(text)).map(entry => entry.0)
  }
  assert_eq(positions("properties", "{\"b\":{},\"a\":true,\"c\":1}"), [
    ["a"],
    ["b"],
  ])
  assert_eq(positions("items", "{}"), [[]])
  assert_eq(positions("items", "[{},false,\"x\"]"), [["0"], ["1"]])
  assert_eq(positions("dependencies", "{\"a\":[\"b\"],\"c\":{}}"), [["c"]])
  assert_eq(positions("not", "false"), [[]])
  for
    name in ["const", "enum", "default", "examples", "x-vendor", "$ref", "$id"] {
    assert_eq(positions(name, "{\"type\":\"string\"}"), [], msg=name)
  }
  assert_true(
    @domain.draft07_dialect("http://json-schema.org/draft-07/schema#"),
  )
  assert_false(
    @domain.draft07_dialect("https://json-schema.org/draft/2020-12/schema"),
  )
}
