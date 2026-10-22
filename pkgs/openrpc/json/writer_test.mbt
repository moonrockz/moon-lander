///|
fn reread(text : String) -> @json.Value {
  @json.parse(text).unwrap().lower().unwrap()
}

///|
test "pretty layout is exact" {
  let value = reread("{\"b\":[1,{}],\"a\":{\"x\":[]},\"c\":\"l\\nm\"}")
  assert_eq(
    @json.write(value, format=@json.Pretty).unwrap(),
    "{\n  \"a\": {\n    \"x\": []\n  },\n  \"b\": [\n    1,\n    {}\n  ],\n  \"c\": \"l\\nm\"\n}",
  )
  assert_eq(@json.write(reread("[]"), format=@json.Pretty).unwrap(), "[]")
  assert_eq(@json.write(reread("7"), format=@json.Pretty).unwrap(), "7")
}

///|
test "unpaired surrogates are refused instead of written" {
  let lone = String::from_array([(0xD800).unsafe_to_char()])
  for
    value in [
      @json.Value::string("a" + lone),
      @json.Value::object([(lone, @json.Value::null())]).unwrap(),
    ] {
    for format in [@json.Compact, @json.Pretty] {
      guard @json.write(value, format~) is Err(d) else {
        fail("unpaired surrogate was written")
      }
      assert_eq(d.code(), @json.InvalidValue)
    }
  }
  // The reader rejects the escaped form too, so writing it could not round-trip.
  assert_true(@json.parse("\"\\ud800\"") is Err(_))
  let pair = @json.Value::string("😀")
  assert_eq(@json.write(pair).unwrap(), "\"😀\"")
}

///|
test "write, read and write is byte-stable in both formats" {
  for
    source in [
      "{\"z\":[9007199254740993,0.10000000000000000001,1e400,-0.00,-0],\"a\":true,\"m\":null}",
      "[\"😀\\u0001\\\"\\\\/\",[[],{}],{\"\":{\"b\":[]}}]", "\"plain\"", "{\"a\":{\"b\":{\"c\":[1,[2,[3]]]}}}",
    ] {
    let value = reread(source)
    for format in [@json.Compact, @json.Pretty] {
      let first = @json.write(value, format~).unwrap()
      let again = reread(first)
      assert_true(again.equals(value).unwrap(), msg=first)
      assert_eq(@json.write(again, format~).unwrap(), first)
    }
  }
}

///|
test "pretty indentation counts toward the output limit" {
  let value = reread("{\"a\":{\"b\":{\"c\":1}}}")
  let compact = @json.write(value).unwrap()
  let limits = @json.Limits::new(max_source=compact.length() + 2)
  assert_true(@json.write(value, limits~) is Ok(_))
  assert_true(@json.write(value, format=@json.Pretty, limits~) is Err(_))
}

///|
test "raw unpaired surrogates are syntax errors, so everything read can be written" {
  let lone = String::from_array([(0xD800).unsafe_to_char()])
  let low = String::from_array([(0xDC00).unsafe_to_char()])
  for
    source in [
      "\"a" + lone + "\"", "{\"" + lone + "\":1}", "[\"" + low + "x\"]", "\"" + lone + "\"",
    ] {
    guard @json.parse(source) is Err(d) else { fail("accepted a lone surrogate") }
    assert_eq(d.code(), @json.Syntax)
    let span = d.span().unwrap()
    assert_eq(span.end() - span.start(), 1)
    let unit = source.code_unit_at(span.start()).to_int()
    assert_true(unit >= 0xD800 && unit <= 0xDFFF)
  }
  let pair = "\"😀\""
  assert_eq(@json.write(reread(pair)).unwrap(), pair)
}
