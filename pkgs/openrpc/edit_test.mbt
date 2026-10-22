///|
test "document edits return a fresh read result and source map" {
  let source = "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\r\n  \"x-meta\": {\"keep\": [1.0]}}"
  let read = @openrpc.read(source)
  let cst = read.cst().unwrap()
  let node = cst.node_at(["x-meta", "keep", "0"]).unwrap()
  let edited = @openrpc.replace_value(
    cst,
    node,
    @exact.Value::number(@exact.Number::parse("2e0").unwrap()),
  ).unwrap()
  assert_eq(
    edited.cst().unwrap().reproduce(),
    source.replace(old="[1.0]", new="[2e0]"),
  )
  let document = edited.document().unwrap()
  assert_true(@openrpc.write(document).unwrap().contains("\"keep\":[2e0]"))
  // A replacement that breaks the document still yields the new CST, with
  // diagnostics located by the new source map.
  let title = edited.cst().unwrap().node_at(["info", "title"]).unwrap()
  let broken = @openrpc.replace_value(
    edited.cst().unwrap(),
    title,
    @exact.Value::number(@exact.Number::parse("17").unwrap()),
  ).unwrap()
  assert_true(broken.document() is None)
  let span = broken.diagnostics()[0].span().unwrap()
  assert_eq(broken.cst().unwrap().slice(span), Some("17"))
}
