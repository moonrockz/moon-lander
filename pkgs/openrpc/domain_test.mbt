///|
test "checked component and extension names enforce their own field rules" {
  for name in ["A", "a-b.c_2", "0"] {
    assert_eq(@openrpc.ComponentKey::parse(name).unwrap().to_string(), name)
  }
  for name in ["", "a/b", "bad key!", "😀"] {
    assert_true(@openrpc.ComponentKey::parse(name) is Err(_))
  }
  for name in ["x-", "x-😀", "x-smithy-error-data"] {
    assert_eq(@openrpc.ExtensionName::parse(name).unwrap().to_string(), name)
  }
  assert_true(@openrpc.ExtensionName::parse("X-name") is Err(_))
  assert_true(@openrpc.ExtensionName::parse("summary") is Err(_))
}

///|
test "error codes are exact mathematical integers beyond host integer ranges" {
  let code = @openrpc.ErrorCode::parse("-90071992547409931234567890").unwrap()
  assert_eq(code.number().token(), "-90071992547409931234567890")
  assert_eq(
    @openrpc.ErrorCode::parse("1.00e2").unwrap().number().token(),
    "1.00e2",
  )
  assert_true(@openrpc.ErrorCode::parse("1.00000000000000000001") is Err(_))
  assert_true(@openrpc.ErrorCode::parse("01") is Err(_))
}

///|
test "extension containers retain exact arbitrary values with checked keys" {
  let value = @exact.parse(
      "{\"x-smithy-error-data\":{\"$ref\":\"literal\",\"n\":9007199254740993},\"x-false\":false}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let extensions = @openrpc.Extensions::from_json(value).unwrap()
  let entries = extensions.entries()
  entries.clear()
  assert_eq(extensions.entries().length(), 2)
  assert_true(extensions.to_json().equals(value).unwrap())
  assert_true(
    extensions.get(@openrpc.ExtensionName::parse("x-false").unwrap()) is Some(_),
  )
  assert_true(
    @openrpc.Extensions::from_json(
      @exact.parse("{\"ordinary\":null}").unwrap().lower().unwrap(),
    )
    is Err(_),
  )
  assert_true(@openrpc.Extensions::from_json(@exact.Value::null()) is Err(_))
}
