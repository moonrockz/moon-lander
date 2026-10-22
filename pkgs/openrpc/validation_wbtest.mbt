///|
test "a schema location is checked once per validation" {
  let value = @exact.parse("{\"enum\":[1,1]}").unwrap().lower().unwrap()
  let schema = @schema.Schema::from_json(value).unwrap()
  let check = Check::{
    index: @reference.SchemaIndex::new(
      @reference.ResourceSet::empty(),
      input=Some(value),
    ),
    findings: [],
    checked: Set([]),
    limits: @exact.Limits::new(),
    version: DocumentVersion::parse("1.4.0").unwrap(),
    profile: Specification,
    links: [],
  }
  check.schema(schema, None, [])
  let first = check.findings.length()
  assert_true(first > 0)
  check.schema(schema, None, [])
  assert_eq(check.findings.length(), first)
}
