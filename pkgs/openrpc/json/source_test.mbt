///|
test "lossless tokens cover every original code unit" {
  let source = " \r\n{\"😀\" : [1e+02, true, false, null, \"a\\\"b\"]}\t"
  let cst = @json.parse(source, source_id=Some("fixture.json")).unwrap()
  let tokens = cst.tokens()
  let rebuilt = StringBuilder()
  let mut end = 0
  for token in tokens {
    assert_eq(token.span().start(), end)
    assert_eq(cst.slice(token.span()).unwrap(), token.text())
    rebuilt.write_string(token.text())
    end = token.span().end()
  }
  assert_eq(end, source.length())
  assert_eq(rebuilt.to_string(), source)
  assert_eq(tokens[0].kind(), @json.Whitespace)
  assert_true(
    tokens.iter().any(t => t.kind() == @json.NumberToken && t.text() == "1e+02"),
  )
}

///|
test "source locations retain duplicate occurrences and member spans" {
  let source = "{\"a\":1,\"\\u0061\":2,\"nested\":{\"a\":3}}"
  let cst = @json.parse(source, source_id=Some("duplicates.json")).unwrap()
  let map = cst.source_map()
  let locations = map.locations(["a"])
  assert_eq(locations.length(), 2)
  assert_eq(locations[0].source_id(), Some("duplicates.json"))
  assert_eq(locations[0].node_index(), 1)
  assert_eq(locations[1].node_index(), 2)
  assert_eq(cst.slice(locations[0].value_span()).unwrap(), "1")
  assert_eq(cst.slice(locations[1].key_span().unwrap()).unwrap(), "\"\\u0061\"")
  assert_eq(map.locations(["nested", "a"]).length(), 1)
  assert_eq(map.locations(["missing"]).length(), 0)
  assert_eq(map.locations([]).length(), 1)
  locations.clear()
  assert_eq(map.locations(["a"]).length(), 2)
}

///|
test "line and column positions use one based UTF16 and CRLF" {
  let source = "\r\n[\"😀\",\r true,\nnull]"
  let map = @json.parse(source).unwrap().source_map()
  let at = map.position(9).unwrap()
  assert_eq(at.line(), 3)
  assert_eq(at.column(), 1)
  let non_bmp = map.position(7).unwrap()
  assert_eq(non_bmp.line(), 2)
  assert_eq(non_bmp.column(), 6)
  let end = map.position(source.length()).unwrap()
  assert_eq(end.line(), 4)
  assert_eq(end.column(), 6)
  assert_true(map.position(-1) is None)
  assert_true(map.position(source.length() + 1) is None)
  let cst = @json.parse("0").unwrap()
  assert_true(cst.slice(@json.Span::new(0, 2).unwrap()) is None)
}

///|
test "replacing a value preserves every other code unit" {
  let source = " \r\n{\"b\" :  [1, 2],\r\n \"a\": {\"x\": true} }\t"
  let cst = @json.parse(source, source_id=Some("doc.json")).unwrap()
  let node = cst.node_at(["b", "1"]).unwrap()
  let value = @json.parse("{\"z\":[null]}").unwrap().lower().unwrap()
  let edited = cst.replace_value(node, value).unwrap()
  assert_eq(
    edited.reproduce(),
    " \r\n{\"b\" :  [1, {\"z\":[null]}],\r\n \"a\": {\"x\": true} }\t",
  )
  assert_eq(edited.source_id(), Some("doc.json"))
  assert_eq(edited.source_map().locations(["b", "1", "z"]).length(), 1)
  let root = edited.replace_value(edited.node_at([]).unwrap(), value).unwrap()
  assert_eq(root.reproduce(), " \r\n{\"z\":[null]}\t")
}

///|
test "stale and foreign node identities are rejected" {
  let cst = @json.parse("{\"a\":1,\"b\":2}").unwrap()
  let node = cst.node_at(["a"]).unwrap()
  let edited = cst.replace_value(node, @json.Value::boolean(true)).unwrap()
  guard edited.replace_value(node, @json.Value::null()) is Err(d) else {
    fail("stale node accepted")
  }
  assert_eq(d.code(), @json.StaleNode)
  let other = @json.parse("{\"a\":1,\"b\":3}").unwrap()
  assert_true(
    other.replace_value(cst.node_at(["b"]).unwrap(), @json.Value::null())
    is Err(_),
  )
  // A separate parse of identical text is the same document.
  let same = @json.parse("{\"a\":1,\"b\":2}").unwrap()
  assert_true(same.replace_value(node, @json.Value::null()) is Ok(_))
  assert_eq(node.index(), cst.source_map().locations(["a"])[0].node().index())
}

///|
test "replacements that exceed limits leave the original unchanged" {
  let source = "{\"a\":1}"
  let cst = @json.parse(source, limits=@json.Limits::new(max_source=12)).unwrap()
  let long = @json.Value::string("0123456789")
  guard cst.replace_value(cst.node_at(["a"]).unwrap(), long) is Err(d) else {
    fail("oversized replacement accepted")
  }
  assert_eq(d.code(), @json.LimitExceeded)
  assert_eq(cst.reproduce(), source)
}
