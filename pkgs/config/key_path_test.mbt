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

///|
fn invalid_reason(text : String) -> String {
  try @config.KeyPath::parse(text) catch {
    InvalidKeyPath(text=found, reason~) => {
      guard found == text else { abort("wrong text \{found}") }
      reason
    }
    error => abort("expected InvalidKeyPath, got \{error.message()}")
  } noraise {
    path => abort("expected \{text} to raise, got \{path}")
  }
}

///|
test "a quoted name can hold a dot" {
  let path = @config.KeyPath::parse("servers.\"eu.west\".port")
  @expect.expect(path.names()).to_equal(["servers", "eu.west", "port"])
  @expect.expect(path.to_string()).to_equal("servers.\"eu.west\".port")
}

///|
test "a quoted name reads the quote and backslash escapes" {
  let path = @config.KeyPath::parse("\"say \\\"hi\\\"\".\"a\\\\b\".\"plain\"")
  @expect.expect(path.names()).to_equal(["say \"hi\"", "a\\b", "plain"])
  @expect.expect(path.to_string()).to_equal("\"say \\\"hi\\\"\".a\\b.plain")
}

///|
test "a bad quoted name is an invalid key path" {
  @expect.expect(invalid_reason("a.\"b")).to_equal(
    "a quoted name has no closing quote",
  )
  @expect.expect(invalid_reason("\"a\\nb\"")).to_equal(
    "a quoted name allows only the escapes \\\" and \\\\",
  )
  @expect.expect(invalid_reason("\"a\"b")).to_equal(
    "a quoted name must end at a dot or at the end",
  )
  @expect.expect(invalid_reason("a\"b\"")).to_equal(
    "a quote can only start a name",
  )
  @expect.expect(invalid_reason("a.\"\"")).to_equal(
    "a name in the key path is empty",
  )
  @expect.expect(invalid_reason("")).to_equal("the key path is empty")
}

///|
test "an invalid key path error message holds the text" {
  try @config.KeyPath::parse("ir..layout") catch {
    error =>
      @expect.expect(error.message()).to_equal(
        "Invalid configuration key path \"ir..layout\": a name in the key path is empty",
      )
  } noraise {
    _ => fail("expected ir..layout to raise")
  }
}

///|
test "from_names takes non-empty names" {
  let path = @config.KeyPath::from_names(["servers", "eu.west"])
  @expect.expect(path).to_equal(@config.KeyPath::parse("servers.\"eu.west\""))
  for names in [[], ["a", ""]] {
    try @config.KeyPath::from_names(names) catch {
      InvalidKeyPath(..) => ()
      _ => fail("expected InvalidKeyPath")
    } noraise {
      _ => fail("expected \{names.join(",")} to raise")
    }
  }
}

///|
/// Generation choices for a key path. Each choice list gives one name over a
/// small alphabet with the characters that need quotes and escapes.
priv struct NamesCase {
  choices : Array[Array[UInt]]
} derive(Debug)

///|
impl @quickcheck.Arbitrary for NamesCase with fn arbitrary(size, state) {
  { choices: @quickcheck.Arbitrary::arbitrary(size, state) }
}

///|
impl @shrink.Shrink for NamesCase with fn shrink(self) {
  @shrink.Shrink::shrink(self.choices).map(choices => { choices, })
}

///|
/// Names stay non-empty when the choices shrink.
fn NamesCase::names(self : NamesCase) -> Array[String] {
  let alphabet = ['a', 'Z', '_', '-', ' ', '.', '"', '\\', 'é', '1']
  let names = self.choices.map(choice => {
    let name = StringBuilder()
    for index in choice {
      name.write_char(alphabet[(index % alphabet.length().reinterpret_as_uint()).reinterpret_as_int()])
    }
    if name.is_empty() {
      "x"
    } else {
      name.to_string()
    }
  })
  if names.is_empty() {
    ["x"]
  } else {
    names
  }
}

///|
test "law: a key path reads back from its text form" {
  @expect.for_all(
    (input : NamesCase) => {
      let path = @config.KeyPath::from_names(input.names())
      let text = path.to_string()
      let read = @config.KeyPath::parse(text)
      @expect.expect(read).to_equal(path)
      @expect.expect(read.to_string()).to_equal(text)
    },
    count=500,
    max_size=12,
    max_shrinks=200,
    seed=3201,
  )
}
