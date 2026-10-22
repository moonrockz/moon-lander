///|
fn main raise {
  for version in ["1.3.2", "1.4.0"] {
    let source = "{\"openrpc\":\"" +
      version +
      "\",\"info\":{\"title\":\"Standalone\",\"version\":\"2026\"},\"methods\":[{\"name\":\"node\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":{\"$ref\":\"#/components/schemas/Node\"}}}],\"components\":{\"schemas\":{\"Node\":{\"type\":\"object\",\"properties\":{\"next\":{\"$ref\":\"#/components/schemas/Node\"}}}}},\"x-vendor\":[9007199254740993,0.10000000000000000001]}"
    let result = @openrpc.read(source)
    assert_true(result.diagnostics().is_empty())
    assert_eq(result.cst().unwrap().reproduce(), source)
    let document = result.document().unwrap()
    let checked = @openrpc.validate_closed(document)
    assert_true(checked.document() is Some(_))
    assert_eq(checked.report().references(), @openrpc.Passed)
    assert_eq(checked.report().artifact(), @openrpc.Passed)
    println(@openrpc.write(document).unwrap())
  }
  let null_schema = @schema.Schema::from_keywords([
    @schema.Type(@schema.TypeConstraint::one(@schema.NullType)),
  ]).unwrap()
  let result = @openrpc.ContentDescriptor::new(
    "result",
    null_schema,
    required=Some(true),
  ).unwrap()
  let example = @openrpc.Example::new(
    @openrpc.LiteralExample(@exact.Value::null()),
    name=Some("result"),
  ).unwrap()
  let pairing = @openrpc.ExamplePairing::new(
    "success",
    [],
    result=Some(@openrpc.Inline(example)),
  ).unwrap()
  let error = @openrpc.ErrorObject::new(
    @openrpc.ErrorCode::parse("1000").unwrap(),
    "Failed",
    data=Some(@exact.Value::null()),
  ).unwrap()
  let op = @openrpc.Method::new(
    @openrpc.MethodName::parse("made").unwrap(),
    [],
    result=Some(@openrpc.Inline(result)),
    examples=Some([@openrpc.Inline(pairing)]),
    errors=Some([@openrpc.Inline(error)]),
    tags=Some([@openrpc.Inline(@openrpc.Tag::new("docs").unwrap())]),
  ).unwrap()
  let components = @openrpc.Components::new(
    schemas=Some([(@openrpc.ComponentKey::parse("Null").unwrap(), null_schema)]),
  ).unwrap()
  let produced = @openrpc.Document::new(
    @openrpc.DocumentVersion::parse("1.4.0").unwrap(),
    @openrpc.Info::new("Produced", "service-v9").unwrap(),
    [@openrpc.Inline(op)],
    components=Some(components),
  ).unwrap()
  println(@openrpc.write(produced).unwrap())
  let names = @schema.keyword_names()
  names.sort()
  println(
    @exact.write(
      @exact.Value::array(names.map(name => @exact.Value::string(name))),
    ).unwrap(),
  )
  let objects = @openrpc.object_kinds().map(kind => {
    let fields = @openrpc.field_names(kind)
    fields.sort()
    (
      kind.name(),
      @exact.Value::array(fields.map(field => @exact.Value::string(field))),
    )
  })
  println(@exact.write(@exact.Value::object(objects).unwrap()).unwrap())
}
