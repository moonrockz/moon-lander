///|
test "JSON Pointer tokens escape once and resolve exact members" {
  let value = @json.parse("{\"a/b\":{\"~key\":[17]},\"\":true,\"~1\":false}")
    .unwrap()
    .lower()
    .unwrap()
  let pointer = @reference.JsonPointer::parse("/a~1b/~0key/0").unwrap()
  assert_eq(pointer.tokens(), ["a/b", "~key", "0"])
  assert_eq(pointer.to_string(), "/a~1b/~0key/0")
  assert_eq(@json.write(pointer.resolve(value).unwrap()).unwrap(), "17")
  assert_eq(
    @json.write(
      @reference.JsonPointer::parse("").unwrap().resolve(value).unwrap(),
    ).unwrap(),
    @json.write(value).unwrap(),
  )
  assert_eq(
    @json.write(
      @reference.JsonPointer::parse("/").unwrap().resolve(value).unwrap(),
    ).unwrap(),
    "true",
  )
  assert_eq(
    @json.write(
      @reference.JsonPointer::parse("/~01").unwrap().resolve(value).unwrap(),
    ).unwrap(),
    "false",
  )
  let copy = pointer.tokens()
  copy[0] = "changed"
  assert_eq(pointer.tokens()[0], "a/b")
}

///|
test "non BMP pointer tokens survive UTF16 copying and escaping" {
  let pointer = @reference.JsonPointer::parse("/🛰~1🌙~0").unwrap()
  assert_eq(pointer.tokens(), ["🛰/🌙~"])
  assert_eq(pointer.to_string(), "/🛰~1🌙~0")
  let root = @json.parse("{\"🛰/🌙~\":true}").unwrap().lower().unwrap()
  assert_eq(@json.write(pointer.resolve(root).unwrap()).unwrap(), "true")
  let escaped = @reference.Reference::parse("#/%F0%9F%9B%B0~1%F0%9F%8C%99~0")
    .unwrap()
    .local_pointer()
    .unwrap()
  assert_eq(escaped.tokens(), pointer.tokens())
}

///|
test "JSON Pointer rejects malformed escapes and array indices" {
  for text in ["x", "/~", "/~2", "/a~01~x"] {
    guard @reference.JsonPointer::parse(text) is Err(d) else { fail(text) }
    assert_eq(d.code(), @json.InvalidReference)
  }
  let value = @json.parse("[true]").unwrap().lower().unwrap()
  for
    text in [
      "/-", "/00", "/01", "/+0", "/1", "/99999999999999999999", "/0/nope",
    ] {
    guard @reference.JsonPointer::parse(text).unwrap().resolve(value) is Err(d) else {
      fail(text)
    }
    assert_eq(d.code(), @json.UnresolvedReference)
  }
}

///|
test "references retain text and decode fragment before pointer escapes" {
  let reference = @reference.Reference::parse("#/caf%C3%A9%2F~01").unwrap()
  assert_eq(reference.text(), "#/caf%C3%A9%2F~01")
  assert_eq(reference.local_pointer().unwrap().tokens(), ["café", "~1"])
  assert_eq(
    @reference.Reference::parse("#").unwrap().local_pointer().unwrap().tokens(),
    [],
  )
  assert_eq(
    @reference.Reference::parse("").unwrap().local_pointer().unwrap().tokens(),
    [],
  )
  assert_true(
    @reference.Reference::parse("other.json#/x").unwrap().local_pointer()
    is None,
  )
  assert_true(
    @reference.Reference::parse("#identifier").unwrap().local_pointer() is None,
  )
  for text in ["#/%", "#/%GG", "#/%FF", "#/~2", "a b", "#a#b"] {
    assert_true(@reference.Reference::parse(text) is Err(_), msg=text)
  }
}

///|
test "a percent-decoded fragment BOM is content rather than a text encoding marker" {
  let reference = @reference.Reference::parse("#%EF%BB%BF/x-ok").unwrap()
  assert_true(reference.local_pointer() is None)
}

///|
test "structured reference fragments distinguish root pointers and identifiers" {
  let pointer = @reference.Reference::parse("schema.json#/%7E01").unwrap()
  assert_eq(pointer.uri().path(), "schema.json")
  guard pointer.fragment() is @reference.PointerFragment(path) else {
    fail("pointer")
  }
  assert_eq(path.tokens(), ["~1"])
  assert_true(
    @reference.Reference::parse("schema.json#").unwrap().fragment()
    is @reference.WholeResource,
  )
  guard @reference.Reference::parse("#name").unwrap().fragment()
    is @reference.IdentifierFragment(name) else {
    fail("identifier")
  }
  assert_eq(name, "name")
  let root = @reference.Reference::parse("other.json").unwrap()
  assert_true(root.fragment() is @reference.WholeResource)
  assert_true(root.local_pointer() is None)
}

///|
test "pointer production copies tokens and enforces explicit resource bounds" {
  let parts = ["a/b", "~key", "🛰"]
  let pointer = @reference.JsonPointer::from_tokens(parts).unwrap()
  parts.clear()
  assert_eq(pointer.tokens(), ["a/b", "~key", "🛰"])
  assert_eq(pointer.to_string(), "/a~1b/~0key/🛰")
  for
    result in [
      @reference.JsonPointer::parse(
        "/a/b",
        limits=@json.Limits::new(max_depth=1),
      ),
      @reference.JsonPointer::from_tokens(
        ["~"],
        limits=@json.Limits::new(max_source=2),
      ),
      @reference.JsonPointer::parse("/a", limits=@json.Limits::new(max_nodes=0)),
    ] {
    guard result is Err(d) else { fail("pointer limit") }
    assert_eq(d.code(), @json.LimitExceeded)
  }
  let pointer = @reference.JsonPointer::parse("/a/b").unwrap()
  let root = @json.parse("{\"a\":{\"b\":true}}").unwrap().lower().unwrap()
  guard pointer.resolve(root, limits=@json.Limits::new(max_depth=1)) is Err(d) else {
    fail("resolve limit")
  }
  assert_eq(d.code(), @json.LimitExceeded)
}
