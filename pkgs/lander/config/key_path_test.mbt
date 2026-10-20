///|
test "a dotted key path holds its names" {
  let path = @config.KeyPath::parse("ir.strict_mode")
  @expect.expect(path.names()).to_equal(["ir", "strict_mode"])
  @expect.expect(path.to_string()).to_equal("ir.strict_mode")
}

///|
test "an empty name is an invalid key path" {
  for text in ["ir..layout", "", ".ir", "ir."] {
    try @config.KeyPath::parse(text) catch {
      error => {
        guard error is InvalidKeyPath(text=found, ..) else {
          fail("expected InvalidKeyPath for \{text}")
        }
        @expect.expect(found).to_equal(text)
      }
    } noraise {
      _ => fail("expected \{text} to raise")
    }
  }
}
