///|
fn full_source(version : String) -> String {
  let source =
    #|{"openrpc":"1.3.2","$schema":"https://meta.open-rpc.org/","info":{"title":"API","version":"service-v9","description":"details","termsOfService":"https://example.test/terms","contact":{"name":"Team","url":"https://example.test/contact","email":"team@example.test"},"license":{"name":"MIT","url":"https://example.test/license"}},"servers":[{"name":"main","url":"https://{host}","summary":"summary","description":"details","variables":{"host":{"default":"example.test","enum":["example.test"],"description":"host"}}}],"externalDocs":{"url":"https://example.test/docs","description":"docs"},"methods":[{"name":"op","params":[{"$ref":"#/components/contentDescriptors/P"}],"result":{"name":"result","schema":{"type":"null"},"summary":"summary","description":"details","required":true,"deprecated":false},"tags":[{"$ref":"#/components/tags/T"},{"name":"inline","summary":"summary","description":"details","externalDocs":{"url":"https://example.test/tag"}}],"summary":"summary","description":"details","externalDocs":{"url":"https://example.test/method"},"deprecated":false,"servers":[],"errors":[{"$ref":"#/components/errors/E"},{"code":1000,"message":"error","data":null}],"links":[{"$ref":"#/components/links/L"},{"name":"inline","method":"op","params":{},"server":{"url":"localhost"}}],"paramStructure":"either","examples":[{"$ref":"#/components/examplePairings/Pair"},{"name":"notification","params":[],"summary":"summary","description":"details"}],"x-smithy-error-data":{"E":{"type":"object"}},"x-smithy-error-examples":{"E":[null]}},{"$ref":"#/x-method"}],"components":{"schemas":{"Node":{"type":"object","properties":{"next":{"$ref":"#/components/schemas/Node"}},"default":{"$ref":"literal"}}},"contentDescriptors":{"P":{"name":"p","schema":{"$ref":"#/components/schemas/Node"},"required":false}},"examples":{"Param":{"name":"p","value":null,"summary":"summary","description":"details","x-smithy-param-structure":"by-name"},"External":{"externalValue":"https://example.invalid/example"}},"links":{"L":{"name":"next","method":"op","summary":"summary","description":"details","params":{"data":{"$ref":"literal"}}}},"errors":{"E":{"code":-90071992547409931234567890,"message":"error","data":{"$ref":"literal","schema":17}}},"tags":{"T":{"name":"tag","summary":"summary","description":"details"}},"examplePairings":{"Pair":{"name":"pair","params":[{"$ref":"#/components/examples/Param"}],"result":{"name":"r","value":null},"summary":"summary","description":"details"}},"examplePairingObjects":{"Historical":{"name":"historical","params":[]}},"x-components":false},"x-method":{"name":"other","params":[]},"x-smithy-protocol":"json-rpc-2.0","x-exact":[9007199254740993,0.10000000000000000001,-0.0,1e400],"future":null}
  source.replace(old="1.3.2", new=version)
}

///|
test "full object graph retains all fields on both supported version lines" {
  for version in ["1.3.2", "1.4.0"] {
    let source = full_source(version)
    let result = @openrpc.read(source)
    assert_true(result.diagnostics().is_empty())
    let document = result.document().unwrap()
    assert_eq(document.info().version(), "service-v9")
    assert_eq(document.schema().unwrap().text(), "https://meta.open-rpc.org/")
    assert_eq(
      document.servers().unwrap()[0].variables().unwrap()[0].1.default_value(),
      "example.test",
    )
    assert_eq(
      document.external_docs().unwrap().url().text(),
      "https://example.test/docs",
    )
    guard document.methods()[0] is @openrpc.Inline(op) else {
      fail("inline method")
    }
    assert_eq(op.tags().unwrap().length(), 2)
    assert_eq(op.errors().unwrap().length(), 2)
    assert_eq(op.links().unwrap().length(), 2)
    assert_eq(op.examples().unwrap().length(), 2)
    assert_eq(op.deprecated(), Some(false))
    assert_eq(op.servers().unwrap().length(), 0)
    assert_eq(op.extensions().entries().length(), 2)
    let components = document.components().unwrap()
    assert_eq(components.schemas().unwrap()[0].0.to_string(), "Node")
    assert_eq(
      components.content_descriptors().unwrap()[0].1.required(),
      Some(false),
    )
    assert_eq(components.examples().unwrap().length(), 2)
    assert_eq(
      components.links().unwrap()[0].1.target_method().unwrap().to_string(),
      "op",
    )
    assert_eq(
      components.errors().unwrap()[0].1.code().number().token(),
      "-90071992547409931234567890",
    )
    assert_eq(components.tags().unwrap()[0].1.summary(), Some("summary"))
    assert_eq(components.example_pairings().unwrap()[0].0.to_string(), "Pair")
    assert_eq(
      components.example_pairing_objects().unwrap()[0].0.to_string(),
      "Historical",
    )
    assert_eq(document.additional_fields().length(), 1)
    assert_true(document.to_json().equals(exact_value(source)).unwrap())
    assert_eq(result.cst().unwrap().reproduce(), source)
    let output = @openrpc.write(document).unwrap()
    assert_eq(
      @openrpc.write(@openrpc.read(output).document().unwrap()).unwrap(),
      output,
    )
  }
}

///|
test "complete producers preserve component spellings and notification results" {
  let document = @openrpc.read(full_source("1.4.1")).document().unwrap()
  let rebuilt = @openrpc.Document::new(
    document.version(),
    document.info(),
    document.methods(),
    schema=document.schema(),
    servers=document.servers(),
    components=document.components(),
    external_docs=document.external_docs(),
    extensions=document.extensions(),
    additional_fields=document.additional_fields(),
  ).unwrap()
  assert_true(rebuilt.to_json().equals(document.to_json()).unwrap())
  let empty = @openrpc.Components::new(
    schemas=Some([]),
    example_pairings=Some([]),
    example_pairing_objects=Some([]),
  ).unwrap()
  assert_true(empty.content_descriptors() is None)
  assert_eq(empty.schemas().unwrap().length(), 0)
  assert_true(empty.to_json().get("examplePairings") is Some(_))
  assert_true(empty.to_json().get("examplePairingObjects") is Some(_))
  let notify = @openrpc.Method::new(
    @openrpc.MethodName::parse("notify").unwrap(),
    [],
  ).unwrap()
  assert_true(notify.result() is None)
  let null_schema = @schema.Schema::from_keywords([
    @schema.Type(@schema.TypeConstraint::one(@schema.NullType)),
  ]).unwrap()
  let result = @openrpc.ContentDescriptor::new("result", null_schema).unwrap()
  let success = @openrpc.Method::new(
    @openrpc.MethodName::parse("success").unwrap(),
    [],
    result=Some(@openrpc.Inline(result)),
  ).unwrap()
  assert_true(success.result() is Some(_))
}

///|
test "new known fields reject wrong shapes without losing the source CST" {
  for
    source in [
      "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\",\"contact\":null},\"methods\":[]}",
      "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\"servers\":[{\"url\":17}]}",
      "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\"components\":{\"errors\":{\"E\":{\"code\":1.5,\"message\":\"bad\"}}}}",
    ] {
    let result = @openrpc.read(source)
    assert_true(result.document() is None, msg=source)
    assert_true(!result.diagnostics().is_empty())
    assert_eq(result.cst().unwrap().reproduce(), source)
  }
}

///|
test "metadata URI fragments are not interpreted as JSON references" {
  let source =
    #|{"openrpc":"1.4.0","$schema":"https://example.test/editor#/raw~2","info":{"title":"URLs","version":"v1","contact":{"url":"https://example.test/contact#/raw~2"},"license":{"url":"https://example.test/license#%FF"}},"externalDocs":{"url":"https://example.test/docs#/raw~2"},"methods":[{"name":"m","params":[],"examples":[{"name":"pair","params":[],"result":{"externalValue":"https://example.test/examples#%FF"}}]}]}
  let result = @openrpc.read(source)
  assert_eq(result.diagnostics().length(), 0)
  let document = result.document().unwrap()
  assert_true(
    document
    .to_json()
    .equals(@exact.parse(source).unwrap().lower().unwrap())
    .unwrap(),
  )
}

///|
test "document reading inherits raised reference token bounds" {
  let pointer = "#" + String::make(300, '/').replace(old="/", new="/x")
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"Bounds\",\"version\":\"v1\"},\"methods\":[{\"$ref\":\"" +
    pointer +
    "\"}]}"
  assert_true(@openrpc.read(source).document() is None)
  let result = @openrpc.read(source, limits=@exact.Limits::unlimited())
  assert_eq(result.diagnostics().length(), 0)
  assert_true(result.document() is Some(_))
}
