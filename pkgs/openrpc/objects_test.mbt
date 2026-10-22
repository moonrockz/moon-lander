///|
fn exact_value(text : String) -> @exact.Value {
  @exact.parse(text).unwrap().lower().unwrap()
}

///|
test "complete metadata objects expose optional fields and shared extensions" {
  let raw = exact_value(
    "{\"title\":\"API\",\"version\":\"service-v9\",\"description\":\"details\",\"termsOfService\":\"https://example.test/terms\",\"contact\":{\"name\":\"Team\",\"url\":\"https://example.test/contact\",\"email\":\"team@example.test\",\"x-data\":null},\"license\":{\"name\":\"MIT\",\"url\":\"https://example.test/license\"},\"future\":false}",
  )
  let info = @openrpc.Info::from_json(raw).unwrap()
  assert_eq(info.description(), Some("details"))
  assert_eq(
    info.terms_of_service().unwrap().text(),
    "https://example.test/terms",
  )
  let contact = info.contact().unwrap()
  assert_eq(contact.name(), Some("Team"))
  assert_eq(contact.email(), Some("team@example.test"))
  assert_eq(contact.extensions().entries().length(), 1)
  assert_eq(info.license().unwrap().name(), Some("MIT"))
  assert_eq(info.additional_fields()[0].0, "future")
  assert_true(info.to_json().equals(raw).unwrap())
  assert_true(
    @openrpc.License::from_json(exact_value("{} ")).unwrap().name() is None,
  )
}

///|
test "server templates and variables retain values without applying defaults" {
  let raw = exact_value(
    "{\"url\":\"https://{host}/{path}\",\"name\":\"production\",\"summary\":\"main\",\"description\":\"details\",\"variables\":{\"host\":{\"default\":\"api.example.test\",\"enum\":[\"api.example.test\"],\"description\":\"host\",\"x-extra\":false},\"path\":{\"default\":\"v1\"}}}",
  )
  let server = @openrpc.Server::from_json(raw).unwrap()
  assert_eq(server.url(), "https://{host}/{path}")
  assert_eq(server.name(), Some("production"))
  assert_eq(
    server.variables().unwrap()[0].1.default_value(),
    "api.example.test",
  )
  assert_eq(
    server.variables().unwrap()[0].1.enum_values(),
    Some(["api.example.test"]),
  )
  let variables = server.variables().unwrap()
  variables.clear()
  assert_true(server.to_json().equals(raw).unwrap())
  let empty = @openrpc.Server::new("localhost").unwrap()
  assert_true(empty.name() is None)
  assert_true(empty.variables() is None)
}

///|
test "example payload distinguishes null external and absent values" {
  let literal = @openrpc.Example::from_json(
    exact_value(
      "{\"name\":\"null\",\"value\":null,\"summary\":\"summary\",\"description\":\"details\",\"x-smithy-param-structure\":\"by-name\"}",
    ),
  ).unwrap()
  assert_true(literal.payload() is @openrpc.LiteralExample(_))
  let external = @openrpc.Example::from_json(
    exact_value("{\"externalValue\":\"https://example.invalid/data\"}"),
  ).unwrap()
  guard external.payload() is @openrpc.ExternalExample(uri) else {
    fail("external")
  }
  assert_eq(uri.text(), "https://example.invalid/data")
  assert_true(
    @openrpc.Example::from_json(exact_value("{} ")).unwrap().payload()
    is @openrpc.NoExampleValue,
  )
  assert_true(
    @openrpc.Example::from_json(
      exact_value("{\"value\":null,\"externalValue\":\"https://example.test\"}"),
    )
    is Err(_),
  )
}

///|
test "errors and link params retain exact literal references as data" {
  let raw = exact_value(
    "{\"code\":-90071992547409931234567890,\"message\":\"Failed\",\"data\":{\"$ref\":\"https://example.invalid/literal\",\"schema\":17},\"x-data\":false}",
  )
  let error = @openrpc.ErrorObject::from_json(raw).unwrap()
  assert_eq(error.code().number().token(), "-90071992547409931234567890")
  assert_true(error.to_json().equals(raw).unwrap())
  let link = @openrpc.Link::from_json(
    exact_value(
      "{\"name\":\"next\",\"summary\":\"summary\",\"description\":\"details\",\"method\":\"target\",\"params\":{\"data\":{\"$ref\":\"literal\"},\"text\":\"{{$result.id}}\"},\"server\":{\"url\":\"localhost\"}}",
    ),
  ).unwrap()
  assert_eq(link.target_method().unwrap().to_string(), "target")
  assert_eq(link.params().unwrap().length(), 2)
  assert_eq(link.server().unwrap().url(), "localhost")
  assert_true(
    @openrpc.ErrorObject::from_json(
      exact_value("{\"code\":1.1,\"message\":\"bad\"}"),
    )
    is Err(_),
  )
  assert_true(
    @openrpc.Link::from_json(exact_value("{\"name\":\"next\",\"params\":[]}"))
    is Err(_),
  )
}

///|
test "immutable producers preserve empty lists and explicit false or null" {
  let names = ["a"]
  let variable = @openrpc.ServerVariable::new("a", enum_values=Some(names)).unwrap()
  names.clear()
  assert_eq(variable.enum_values(), Some(["a"]))
  let example = @openrpc.Example::new(
    @openrpc.LiteralExample(@exact.Value::null()),
    name=Some("null"),
  ).unwrap()
  let params = [@openrpc.Inline(example)]
  let pairing = @openrpc.ExamplePairing::new(
    "empty-result",
    params,
    summary=Some("summary"),
  ).unwrap()
  params.clear()
  assert_eq(pairing.params().length(), 1)
  assert_true(pairing.result() is None)
  let docs = @openrpc.ExternalDocumentation::from_json(
    exact_value("{\"url\":\"https://example.test/docs\"}"),
  ).unwrap()
  let tag = @openrpc.Tag::new(
    "tag",
    summary=Some("summary"),
    external_docs=Some(docs),
  ).unwrap()
  assert_eq(
    tag.external_docs().unwrap().url().text(),
    "https://example.test/docs",
  )
}

///|
test "link name presence is retained for version specific conformance checks" {
  let link = @openrpc.Link::from_json(exact_value("{} ")).unwrap()
  assert_true(link.name() is None)
  assert_true(@openrpc.Link::new().unwrap().name() is None)
}
