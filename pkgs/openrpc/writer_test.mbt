///|
test "document writing laws hold in both formats" {
  for version in ["1.3.2", "1.4.0"] {
    let document = @openrpc.read(full_source(version)).document().unwrap()
    let model = @exact.write(document.to_json()).unwrap()
    for format in [@exact.Compact, @exact.Pretty] {
      let first = @openrpc.write(document, format~).unwrap()
      let reread = @openrpc.read(first).document().unwrap()
      // The AST keeps every present field and exact token.
      assert_eq(@exact.write(reread.to_json()).unwrap(), model, msg=version)
      assert_eq(@openrpc.write(reread, format~).unwrap(), first)
    }
  }
}

///|
test "writing keeps orders, absences, spellings and references" {
  let source = "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"name\":\"z\",\"params\":[{\"name\":\"b\",\"schema\":{\"enum\":[3,1,2]}},{\"$ref\":\"#/components/contentDescriptors/A\"}]},{\"name\":\"a\",\"params\":[]}],\"components\":{\"contentDescriptors\":{\"A\":{\"name\":\"a\",\"schema\":true}},\"examplePairingObjects\":{\"P\":{\"name\":\"p\",\"params\":[]}}},\"x-n\":1.0}"
  let document = @openrpc.read(source).document().unwrap()
  let text = @openrpc.write(document).unwrap()
  assert_true(text.contains("\"methods\":[{\"name\":\"z\""), msg=text)
  assert_true(text.contains("\"enum\":[3,1,2]"))
  assert_true(text.contains("{\"$ref\":\"#/components/contentDescriptors/A\"}"))
  assert_true(text.contains("\"examplePairingObjects\""))
  assert_false(text.contains("examplePairings\""))
  assert_false(text.contains("paramStructure"))
  assert_false(text.contains("deprecated"))
  assert_true(text.contains("\"x-n\":1.0"))
}
