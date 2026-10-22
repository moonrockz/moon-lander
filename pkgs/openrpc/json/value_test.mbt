///|
test "numeric comparison orders exact coefficients without exponent expansion" {
  for
    (a, b, expected) in [
      ("-0", "0.0", 0),
      ("9007199254740992", "9007199254740993", -1),
      ("-1.1", "-1.01", -1),
      ("1e99999999999999999999", "9e99999999999999999998", 1),
      ("1e-99999999999999999999", "9e-99999999999999999998", -1),
      ("100e-2", "1.00", 0),
      ("0.1", "-1000", 1),
      ("1.0000000000000000001", "1", 1),
    ] {
    let left = @json.Number::parse(a).unwrap()
    let right = @json.Number::parse(b).unwrap()
    assert_eq(left.numeric_compare(right), expected, msg=a + " versus " + b)
    assert_eq(right.numeric_compare(left), -expected)
  }
}

///|
test "exact value equality distinguishes numeric spelling but not object order" {
  let a = @json.parse("{\"a\":[1.0,null],\"b\":true}").unwrap().lower().unwrap()
  let b = @json.parse("{\"b\":true,\"a\":[1,null]}").unwrap().lower().unwrap()
  assert_false(a.equals(b).unwrap())
  assert_true(a.equals(b, numeric=true).unwrap())
  assert_true(
    a
    .equals(
      @json.parse("{\"b\":true,\"a\":[1.0,null]}").unwrap().lower().unwrap(),
    )
    .unwrap(),
  )
  assert_false(
    a
    .equals(
      @json.parse("{\"a\":[null,1.0],\"b\":true}").unwrap().lower().unwrap(),
      numeric=true,
    )
    .unwrap(),
  )
}

///|
test "core interop preserves repr and isolates mutable collections" {
  let number = Json::number(9007199254740992.0, repr="9007199254740993")
  let items = [number]
  let exact = @json.from_core_json(Json::array(items)).unwrap()
  items.clear()
  assert_eq(@json.write(exact).unwrap(), "[9007199254740993]")
  guard @json.to_core_json(exact).unwrap() is Json::Array(values) else {
    fail("array")
  }
  guard values[0] is Json::Number(_, repr=Some(token)) else { fail("repr") }
  assert_eq(token, "9007199254740993")
  values.clear()
  assert_eq(@json.write(exact).unwrap(), "[9007199254740993]")
  let rounded = @json.from_core_json(Json::number(9007199254740992.0)).unwrap()
  assert_true(
    rounded
    .equals(
      @json.parse("9007199254740992").unwrap().lower().unwrap(),
      numeric=true,
    )
    .unwrap(),
  )
  assert_true(@json.from_core_json(Json::number(1.0, repr="01")) is Err(_))
  assert_true(@json.from_core_json(Json::number(1.0 / 0.0)) is Err(_))
  let enormous = @json.parse("1e400").unwrap().lower().unwrap()
  assert_true(
    @json.from_core_json(@json.to_core_json(enormous).unwrap())
    .unwrap()
    .equals(enormous)
    .unwrap(),
  )
  let huge_exponent = @json.parse("-1e99999999999999999999")
    .unwrap()
    .lower()
    .unwrap()
  assert_true(
    @json.from_core_json(@json.to_core_json(huge_exponent).unwrap())
    .unwrap()
    .equals(huge_exponent)
    .unwrap(),
  )
}

///|
test "interop traversal is stack safe and bounded for cyclic core arrays" {
  let mut core = Json::null()
  for _ in 0..<2000 {
    core = Json::array([core])
  }
  let limits = @json.Limits::unlimited()
  let exact = @json.from_core_json(core, limits~).unwrap()
  assert_true(
    @json.from_core_json(@json.to_core_json(exact, limits~).unwrap(), limits~)
    .unwrap()
    .equals(exact, limits~)
    .unwrap(),
  )
  let cyclic = []
  let root = Json::array(cyclic)
  cyclic.push(root)
  guard @json.from_core_json(root, limits=@json.Limits::new(max_nodes=10))
    is Err(d) else {
    fail("cycle ignored budget")
  }
  assert_eq(d.code(), @json.LimitExceeded)
}

///|
test "value equality reports bounded exhaustion for shared subtrees" {
  let mut left = @json.Value::null()
  let mut right = @json.Value::null()
  for _ in 0..<40 {
    left = @json.Value::array([left, left])
    right = @json.Value::array([right, right])
  }
  guard left.equals(right, limits=@json.Limits::new(max_nodes=100)) is Err(d) else {
    fail("equality ignored its bound")
  }
  assert_eq(d.code(), @json.LimitExceeded)
}

///|
test "core import reserves pending nodes before expanding a cyclic container" {
  let entries = Array::make(5000, Json::null())
  let cyclic = Json::array(entries)
  entries[0] = cyclic
  guard @json.from_core_json(
      cyclic,
      limits=@json.Limits::new(max_nodes=10000, max_depth=128),
    )
    is Err(d) else {
    fail("cycle was imported")
  }
  assert_eq(d.code(), @json.LimitExceeded)
  assert_eq(d.message(), "Core JSON import node limit exceeded")
}

///|
test "value equality bounds aggregate text and numeric tokens" {
  let a = @json.Value::array([
    @json.Value::string("ab"),
    @json.Value::string("cd"),
  ])
  assert_true(a.equals(a, limits=@json.Limits::new(max_source=3)) is Err(_))
  let number = @json.Value::number(@json.Number::parse("1234").unwrap())
  assert_true(
    number.equals(number, numeric=true, limits=@json.Limits::new(max_number=3))
    is Err(_),
  )
}

///|
test "writer reserves pending value nodes before expanding shared containers" {
  let mut value = @json.Value::null()
  for _ in 0..<129 {
    value = @json.Value::array(Array::make(5000, value))
  }
  guard @json.write(
      value,
      limits=@json.Limits::new(max_nodes=10000, max_depth=128),
    )
    is Err(d) else {
    fail("writer ignored its node bound")
  }
  assert_eq(d.code(), @json.LimitExceeded)
  assert_eq(d.message(), "JSON output node limit exceeded")
}

///|
test "array lookup exposes immutable children without a collection view" {
  let value = @json.Value::array([
    @json.Value::null(),
    @json.Value::string("kept"),
  ])
  assert_eq(value.array_length(), Some(2))
  assert_eq(value.array_item(1).unwrap().text(), Some("kept"))
  assert_true(value.array_item(-1) is None)
  assert_true(value.array_item(2) is None)
  assert_true(@json.Value::null().array_length() is None)
  assert_true(@json.Value::string("text").array_item(0) is None)
}
