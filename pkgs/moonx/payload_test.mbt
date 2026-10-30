///|
test "portable payload paths preserve exact valid asset names" {
  for input in ["a", "A", "0", "_", "-", "!", "}", "package.json", "lib/runtime/a-b_1.mjs", "a b/file.js", "COM0", "COM10", "LPT0", "LPT10", "console.js", " aux-file"] {
    assert_eq(@moonx.RelativeFilePath::parse(input).to_string(), input)
  }
}

///|
test "portable payload rules reject both sides of lexical boundaries" {
  let cases : Array[(String, @moonx.PayloadPathRule)] = [
    ("", Empty), ("/a", Absolute), ("//host/a", Absolute),
    ("a//b", EmptySegment), ("a/", EmptySegment),
    (".", DotSegment), ("a/./b", DotSegment),
    ("..", ParentSegment), ("a/../b", ParentSegment),
    ("a\\b", Backslash), ("C:\\a", ReservedCharacter),
    ("a\u{0}", ControlCharacter), ("a\u{1f}", ControlCharacter),
    ("a\u{7f}", ControlCharacter), ("a\u{80}", NonAscii), ("é.js", NonAscii),
    ("a<", ReservedCharacter), ("a>", ReservedCharacter),
    ("C:a", ReservedCharacter), ("a:b", ReservedCharacter),
    ("a\"", ReservedCharacter), ("a|", ReservedCharacter),
    ("a?", ReservedCharacter), ("a*", ReservedCharacter),
    ("a~", ReservedCharacter),
    ("a.", TrailingDotOrSpace), ("a ", TrailingDotOrSpace),
    ("a. /b", TrailingDotOrSpace), ("con", ReservedName),
    ("CON.txt", ReservedName), ("con .txt", ReservedName),
    ("prn", ReservedName), ("AUX", ReservedName), ("nul.js", ReservedName),
    ("COM1.js", ReservedName), ("com9", ReservedName),
    ("LPT1.txt", ReservedName), ("lpt9", ReservedName),
    ("CONIN$", ReservedName), ("conout$", ReservedName), ("clock$", ReservedName),
  ]
  for (input, expected) in cases {
    try @moonx.RelativeFilePath::parse(input) catch {
      @moonx.PayloadPathError::InvalidPayloadPath(input=actual, rule~) => {
        assert_eq(actual, input)
        assert_eq(rule, expected, msg=input)
      }
    } noraise { _ => fail("Invalid asset path accepted: " + input) }
  }
}

///|
fn file(path : String, bytes~ : Bytes = b"") -> @moonx.PayloadFile raise {
  @moonx.PayloadFile::new(@moonx.RelativeFilePath::parse(path), bytes)
}

///|
test "payload keeps exact binary entries and owns array boundaries" {
  let bytes = b"\x00\xff\x01\n"
  let inputs = [file("package.json", bytes=b"{}"), file("dist/entry.mjs", bytes~)]
  let payload = @moonx.Payload::new(inputs, @moonx.RelativeFilePath::parse("dist/entry.mjs"))
  inputs.clear()
  let output = payload.files()
  assert_eq(output[1].bytes(), bytes)
  assert_eq(output[1].path().to_string(), "dist/entry.mjs")
  assert_eq(payload.entry().to_string(), "dist/entry.mjs")
  output.clear()
  assert_eq(payload.files().length(), 2)
}

///|
test "payload rejects normalized duplicates in either order" {
  for paths in [["entry.js", "entry.js"], ["entry.js", "ENTRY.JS"], ["ENTRY.JS", "entry.js"]] {
    try @moonx.Payload::new(paths.map(path => file(path)), @moonx.RelativeFilePath::parse(paths[0])) catch {
      @moonx.PayloadError::DuplicatePayloadPath(first~, second~) => {
        assert_eq(first.to_string(), paths[0])
        assert_eq(second.to_string(), paths[1])
      }
      _ => fail("Expected DuplicatePayloadPath")
    } noraise { _ => fail("Duplicate payload accepted") }
  }
}

///|
test "payload rejects file-directory conflicts in either order and case" {
  for paths in [["lib", "lib/a.js"], ["lib/a.js", "lib"], ["LIB", "lib/a.js"]] {
    try @moonx.Payload::new(paths.map(path => file(path)), @moonx.RelativeFilePath::parse(paths[0])) catch {
      @moonx.PayloadError::PayloadFileDirectoryConflict(file~, descendant~) => {
        assert_true(!file.to_string().contains("/"))
        assert_eq(descendant.to_string(), "lib/a.js")
      }
      _ => fail("Expected PayloadFileDirectoryConflict")
    } noraise { _ => fail("File-directory collision accepted") }
  }
}

///|
test "payload rejects inconsistent directory spelling across case-sensitive hosts" {
  try @moonx.Payload::new([file("lib/a.js"), file("LIB/b.js")], @moonx.RelativeFilePath::parse("lib/a.js")) catch {
    @moonx.PayloadError::PayloadDirectoryCaseConflict(first~, second~) => {
      assert_eq(first.to_string(), "lib/a.js")
      assert_eq(second.to_string(), "LIB/b.js")
    }
    _ => fail("Expected PayloadDirectoryCaseConflict")
  } noraise { _ => fail("Ambiguous directory spelling accepted") }
}

///|
test "payload requires exact entry membership including empty collection" {
  for paths in [[], ["other.js"], ["ENTRY.JS"]] {
    try @moonx.Payload::new(paths.map(path => file(path)), @moonx.RelativeFilePath::parse("entry.js")) catch {
      @moonx.PayloadError::PayloadEntryMissing(entry~) => assert_eq(entry.to_string(), "entry.js")
      _ => fail("Expected PayloadEntryMissing")
    } noraise { _ => fail("Missing entry accepted") }
  }
}

///|
test "Node launch contains a complete payload and opaque Unicode arguments" {
  let payload = @moonx.Payload::new([file("entry.mjs")], @moonx.RelativeFilePath::parse("entry.mjs"))
  let args = @moonx.Arguments::parse(["", "é🙂", "--", "a\nb"])
  let plan = @moonx.NodeLaunch::new(payload, args)
  assert_eq(plan.executable().to_string(), "node")
  assert_eq(plan.payload().entry().to_string(), "entry.mjs")
  assert_eq(plan.arguments().to_array(), args.to_array())
}
