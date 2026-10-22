///|
test "public reader and writer retain values on both supported version lines" {
  for version in ["1.3.2", "1.4.19"] {
    let source = "{\"methods\":[],\"info\":{\"title\":\"Independent\",\"version\":\"service-v9\"},\"openrpc\":\"" +
      version +
      "\",\"x-vendor\":{\"small\":1e-400,\"big\":9007199254740993}}"
    let result = @openrpc.read(source)
    let document = result.document().unwrap()
    let output = @openrpc.write(document).unwrap()
    assert_eq(
      output,
      "{\"info\":{\"title\":\"Independent\",\"version\":\"service-v9\"},\"methods\":[],\"openrpc\":\"" +
      version +
      "\",\"x-vendor\":{\"big\":9007199254740993,\"small\":1e-400}}",
    )
    assert_eq(
      @openrpc.read(output).document().unwrap().info().version(),
      "service-v9",
    )
  }
}

///|
test "missing schema references fail while ordinary extension references remain data" {
  let document = @openrpc.read(
      "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":{\"$ref\":\"#/components/schemas/Missing\"}}}],\"x-vendor\":{\"$ref\":\"https://example.invalid/literal\"}}",
    )
    .document()
    .unwrap()
  let result = @openrpc.validate_closed(document)
  assert_true(result.document() is None)
  assert_eq(result.report().references(), @openrpc.Failed)
  assert_eq(
    result
    .report()
    .findings()
    .filter(f => f.diagnostic().code() == @exact.UnresolvedReference)
    .length(),
    1,
  )
}

///|
test "malformed component schemas fail typed reading at their own document path" {
  let result = @openrpc.read(
    "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"op\",\"params\":[],\"result\":{\"name\":\"result\",\"schema\":{\"$ref\":\"#/components/schemas/S\"}}}],\"components\":{\"schemas\":{\"S\":{\"properties\":{\"bad\":42}}}}}",
  )
  assert_true(result.document() is None)
  let diagnostics = result.diagnostics()
  assert_true(
    diagnostics.any(d => {
      d.code() == @exact.InvalidSchema &&
      d.path() == ["components", "schemas", "S", "properties", "bad"]
    }),
  )
  assert_true(
    diagnostics
    .filter(d => d.code() == @exact.InvalidSchema)
    .all(d => d.path() == ["components", "schemas", "S", "properties", "bad"]),
  )
}
