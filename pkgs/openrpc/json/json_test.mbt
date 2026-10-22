///|
test "source reproduction and exact canonical numbers" {
  let source = " \r\n{\"z\": [9007199254740993, 0.10000000000000000001, 1e400, -0.00], \"a\":true}\t"
  let cst = @json.parse(source).unwrap()
  assert_eq(cst.reproduce(), source)
  let value = cst.lower().unwrap()
  assert_eq(
    @json.write(value).unwrap(),
    "{\"a\":true,\"z\":[9007199254740993,0.10000000000000000001,1e400,-0.00]}",
  )
}

///|
test "duplicate decoded names retain CST and fail lowering" {
  let source = "{\"name\":1,\"\\u006eame\":2}"
  let cst = @json.parse(source).unwrap()
  assert_eq(cst.reproduce(), source)
  guard cst.lower() is Err(findings) else { fail("duplicate was accepted") }
  assert_true(findings.iter().any(d => d.code() == @json.DuplicateKey))
}

///|
test "strict syntax rejects non JSON and malformed numbers" {
  for
    source in [
      "[1,]", "{\"a\":1,}", "01", "1.", "1e", "true false", "/*x*/null", "[1 2]",
    ] {
    assert_true(@json.parse(source) is Err(_), msg=source)
  }
}

///|
test "limits return structured exhaustion" {
  let limits = @json.Limits::new(max_depth=2)
  guard @json.parse("[[[0]]]", limits~) is Err(d) else { fail("depth ignored") }
  assert_eq(d.code(), @json.LimitExceeded)
}

///|
test "number equality is exact and independent of spelling" {
  assert_true(
    @json.Number::parse("1.00")
    .unwrap()
    .numeric_equal(@json.Number::parse("1e0").unwrap()),
  )
  assert_false(
    @json.Number::parse("9007199254740992")
    .unwrap()
    .numeric_equal(@json.Number::parse("9007199254740993").unwrap()),
  )
  assert_true(
    @json.Number::parse("-0e999999999999999999999")
    .unwrap()
    .numeric_equal(@json.Number::parse("0").unwrap()),
  )
  assert_true(@json.Number::parse("01") is Err(_))
}

///|
test "numeric exponent and integrality do not expand powers of ten" {
  assert_true(
    @json.Number::parse("1e+2")
    .unwrap()
    .numeric_equal(@json.Number::parse("100").unwrap()),
  )
  assert_true(@json.Number::parse("100e-2").unwrap().is_integer())
  assert_false(
    @json.Number::parse("1.0000000000000000001").unwrap().is_integer(),
  )
  assert_true(
    @json.Number::parse("10e999999999999999999999").unwrap().is_integer(),
  )
}

///|
test "immutable collection boundaries do not change canonical output" {
  let fields = [("x", @json.Value::string("before"))]
  let value = @json.Value::object(fields).unwrap()
  fields[0] = ("x", @json.Value::string("after"))
  guard value.kind() is @json.Object(copy) else { fail("expected object") }
  copy.clear()
  assert_eq(@json.write(value).unwrap(), "{\"x\":\"before\"}")
}

///|
test "iterative syntax lowering and writing survive deeply nested input" {
  let source = "[".repeat(2000) + "0" + "]".repeat(2000)
  let limits = @json.Limits::new(max_depth=2001)
  let cst = @json.parse(source, limits~).unwrap()
  assert_eq(@json.write(cst.lower().unwrap(), limits~).unwrap(), source)
}

///|
test "node spans and paths cover escaped keys and non BMP source" {
  let source = "{\"😀\":{\"\\u0061\":false}}"
  let cst = @json.parse(source).unwrap()
  let span = cst.span_at(["😀", "a"]).unwrap()
  assert_eq(source[span.start():span.end()].to_owned(), "false")
  assert_eq(cst.path(2), Some(["😀", "a"]))
}

///|
test "duplicate diagnostics obey an explicit finding bound" {
  let source = "{\"x\":0" + ",\"x\":1".repeat(10000) + "}"
  let cst = @json.parse(source, limits=@json.Limits::new(max_findings=3)).unwrap()
  guard cst.lower() is Err(findings) else { fail("duplicates were accepted") }
  assert_eq(findings.length(), 3)
  assert_eq(findings[2].code(), @json.LimitExceeded)
  assert_eq(findings[0].path(), ["x"])
}
