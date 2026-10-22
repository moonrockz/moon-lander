///|
fn raw(source : String) -> @json.Value {
  @json.parse(source).unwrap().lower().unwrap()
}

///|
test "schema objects share checked document extensions" {
  let extensions = @domain.Extensions::from_json(
    raw("{\"x-data\":{\"$ref\":\"literal\"}} "),
  ).unwrap()
  let schema = @schema.Schema::from_keywords([], extensions~).unwrap()
  guard schema.kind() is @schema.ObjectSchema(object) else {
    fail("object schema")
  }
  assert_true(
    object.extensions().to_json().equals(extensions.to_json()).unwrap(),
  )
  let entries = extensions.entries()
  let rebuilt = @domain.Extensions::from_entries(entries).unwrap()
  entries.clear()
  assert_eq(rebuilt.entries().length(), 1)
  let name = @domain.ExtensionName::parse("x-a").unwrap()
  assert_true(
    @domain.Extensions::from_entries([
      (name, @json.Value::null()),
      (name, @json.Value::null()),
    ])
    is Err(_),
  )
  assert_eq(@domain.Extensions::empty().entries().length(), 0)
}

///|
test "every draft07 keyword has a typed exact alternative" {
  let source =
    #|{"$id":"urn:example:Root","$schema":"http://json-schema.org/draft-07/schema#","$comment":"comment","title":"title","description":"description","default":{"$ref":"literal"},"readOnly":false,"writeOnly":true,"examples":[null,{"schema":17}],"multipleOf":0.10000000000000000001,"maximum":9007199254740993,"exclusiveMaximum":1e400,"minimum":-0,"exclusiveMinimum":-1,"maxLength":1e400,"minLength":0,"pattern":"[a-z]","additionalItems":false,"items":[true,{}],"maxItems":10,"minItems":0,"uniqueItems":false,"contains":true,"maxProperties":10,"minProperties":0,"required":[],"additionalProperties":true,"definitions":{"x-data":false},"properties":{"$id":true},"patternProperties":{"^x-":{}},"dependencies":{"names":["a"],"schema":false},"propertyNames":true,"const":{"$ref":"literal"},"enum":[1,2],"type":["object","null"],"format":"anything","contentMediaType":"application/json","contentEncoding":"base64","if":true,"then":{},"else":false,"allOf":[true],"anyOf":[{}],"oneOf":[false],"not":false}
  let value = raw(source)
  let schema = @schema.Schema::from_json(value).unwrap()
  guard schema.kind() is @schema.ObjectSchema(object) else { fail("object") }
  assert_eq(object.keywords().length(), 45)
  assert_eq(object.additional_fields().length(), 0)
  assert_true(schema.to_json().equals(value).unwrap())
  let names = object.keywords().map(k => k.name())
  names.push("$ref")
  names.sort()
  let inventory = @schema.keyword_names()
  inventory.sort()
  assert_eq(names, inventory)
  assert_eq(inventory.length(), 46)
  guard object.keyword("items").unwrap()
    is @schema.Items(@schema.TupleItems(items)) else {
    fail("tuple")
  }
  assert_eq(items.length(), 2)
  assert_true(items[0].kind() is @schema.BooleanSchema(true))
  guard object.keyword("maximum").unwrap() is @schema.Maximum(number) else {
    fail("number")
  }
  assert_eq(number.token(), "9007199254740993")
  guard object.keyword("maxLength").unwrap() is @schema.MaxLength(count) else {
    fail("count")
  }
  assert_eq(count.number().token(), "1e400")
}

///|
test "schema type and exact numeric constructors reject invalid local values" {
  assert_true(@schema.TypeConstraint::many([]) is Err(_))
  assert_true(
    @schema.TypeConstraint::many([@schema.StringType, @schema.StringType])
    is Err(_),
  )
  assert_true(@schema.NonNegativeInteger::parse("-1") is Err(_))
  assert_true(@schema.NonNegativeInteger::parse("1.5") is Err(_))
  assert_eq(
    @schema.NonNegativeInteger::parse("-0.0").unwrap().number().token(),
    "-0.0",
  )
  assert_true(@schema.PositiveNumber::parse("0") is Err(_))
  assert_true(@schema.PositiveNumber::parse("-1") is Err(_))
  assert_eq(
    @schema.PositiveNumber::parse("1e-400").unwrap().number().token(),
    "1e-400",
  )
  for
    source in [
      "{\"type\":17}", "{\"type\":[]}", "{\"items\":[]}", "{\"allOf\":[]}", "{\"dependencies\":{\"x\":[1]}}",
      "{\"properties\":{\"x\":null}}", "{\"multipleOf\":0}", "{\"minItems\":1.5}",
    ] {
    assert_true(@schema.Schema::from_json(raw(source)) is Err(_), msg=source)
  }
}

///|
test "schema dictionaries and literal data have different traversal rules" {
  let value = raw(
    "{\"properties\":{\"$id\":false,\"x-thing\":true},\"default\":{\"type\":17},\"examples\":[{\"properties\":null}],\"const\":{\"$ref\":\"bad pointer\"},\"custom\":{\"type\":17},\"x-schema\":{\"schema\":17}}",
  )
  let schema = @schema.Schema::from_json(value).unwrap()
  guard schema.kind() is @schema.ObjectSchema(object) else { fail("object") }
  assert_eq(object.additional_fields().length(), 1)
  assert_eq(object.additional_fields()[0].0, "custom")
  assert_eq(object.extensions().entries().length(), 1)
  guard object.keyword("properties").unwrap() is @schema.Properties(properties) else {
    fail("properties")
  }
  assert_eq(properties.length(), 2)
  properties.clear()
  assert_true(schema.to_json().equals(value).unwrap())
  let reference = @schema.Schema::from_json(
    raw("{\"$ref\":\"#/ok\",\"type\":17,\"properties\":false}"),
  ).unwrap()
  guard reference.kind() is @schema.ReferenceSchema(ref_) else {
    fail("reference")
  }
  assert_eq(ref_.reference().text(), "#/ok")
  assert_true(ref_.siblings().get("type") is Some(_))
  let foreign = @schema.Schema::from_json(
    raw(
      "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"type\":17}",
    ),
  ).unwrap()
  assert_true(foreign.kind() is @schema.UnsupportedDialectSchema(_, _))
}

///|
test "typed construction copies collections and retains explicit presence" {
  let types = [@schema.ObjectType, @schema.NullType]
  let constraint = @schema.TypeConstraint::many(types).unwrap()
  types.clear()
  let required = ["a"]
  let keywords = [
    @schema.Type(constraint),
    @schema.Required(required),
    @schema.Default(@json.Value::null()),
    @schema.ReadOnly(false),
  ]
  let schema = @schema.Schema::from_keywords(keywords).unwrap()
  keywords.clear()
  required.clear()
  assert_true(
    schema
    .to_json()
    .equals(
      raw(
        "{\"type\":[\"object\",\"null\"],\"required\":[\"a\"],\"default\":null,\"readOnly\":false}",
      ),
    )
    .unwrap(),
  )
  assert_true(
    @schema.Schema::from_keywords([@schema.Title("a"), @schema.Title("b")])
    is Err(_),
  )
  assert_true(@schema.Schema::from_keywords([@schema.AllOf([])]) is Err(_))
  guard schema.kind() is @schema.ObjectSchema(object) else { fail("object") }
  guard object.keyword("required").unwrap() is @schema.Required(names) else {
    fail("required")
  }
  names.clear()
  assert_true(schema.to_json().get("required") is Some(_))
}

///|
test "schema decoding is iterative and obeys explicit resource bounds" {
  let source = "{\"items\":".repeat(2000) + "true" + "}".repeat(2000)
  let limits = @json.Limits::unlimited()
  let value = @json.parse(source, limits~).unwrap().lower().unwrap()
  let schema = @schema.Schema::from_json(value, limits~).unwrap()
  assert_eq(@json.write(schema.to_json(), limits~).unwrap(), source)
  assert_true(@schema.Schema::from_json(schema.to_json()) is Err(_))
}

///|
test "raised schema reference bounds remain valid through typed getters" {
  let pointer = "#" + String::make(300, '/').replace(old="/", new="/x")
  let value = @json.Value::object([("$ref", @json.Value::string(pointer))]).unwrap()
  assert_true(@schema.Schema::from_json(value) is Err(_))
  guard @schema.Schema::from_json(value, limits=@json.Limits::unlimited())
    is Ok(schema) else {
    fail("raised constructor bounds must be inherited")
  }
  guard schema.kind() is @schema.ReferenceSchema(object) else {
    fail("reference")
  }
  assert_eq(object.reference().local_pointer().unwrap().tokens().length(), 300)
}
