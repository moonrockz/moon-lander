///|
test "executables parse once without changing opaque path text" {
  for text in ["node", "node.exe", "/a path/node", "C:\\a path\\node.exe", "é🙂"] {
    assert_eq(@moonx.Executable::parse(text).to_string(), text)
  }
  assert_eq(@moonx.Executable::node().to_string(), "node")
}

///|
test "executable errors name the input and rule" {
  for input in ["", "a\u{0}b"] {
    try @moonx.Executable::parse(input) catch {
      @moonx.ExecutableError::InvalidExecutable(input=actual, rule=actual_rule) => {
        assert_eq(actual, input)
        match (input, actual_rule) {
          ("", Empty) | ("a\u{0}b", ContainsNul) => ()
          _ => fail("Wrong executable rule")
        }
      }
    } noraise { _ => fail("Invalid executable accepted") }
  }
}

///|
test "argument arrays preserve empty elements delimiters Unicode and newlines" {
  let inputs = ["", "--", "--a=b", "a b", "é🙂", "a\nb", "\"\\[]{}"]
  assert_eq(@moonx.Arguments::parse(inputs).to_array(), inputs)
  assert_eq(@moonx.Arguments::empty().to_array(), [])
}

///|
test "arguments reject only NUL and retain its position" {
  try @moonx.Arguments::parse(["", "before", "a\u{0}b"]) catch {
    @moonx.ArgumentsError::ArgumentContainsNul(input~, index~) => {
      assert_eq(input, "a\u{0}b")
      assert_eq(index, 2)
    }
  } noraise { _ => fail("NUL argument accepted") }
}

///|
test "argument values own their input and output arrays" {
  let input = ["original"]
  let arguments = @moonx.Arguments::parse(input)
  input[0] = "changed input"
  let output = arguments.to_array()
  output[0] = "changed output"
  assert_eq(arguments.to_array(), ["original"])
}

///|
test "commands contain typed executable and arguments" {
  let command = @moonx.Command::new(@moonx.Executable::node(), @moonx.Arguments::parse(["--", ""]))
  assert_eq(command.executable().to_string(), "node")
  assert_eq(command.arguments().to_array(), ["--", ""])
}

///|
test "shutdown grace tests both sides of its lower limit and maximum" {
  for milliseconds in [1, 5000, 2147483647] {
    assert_eq(@moonx.ShutdownGrace::from_milliseconds(milliseconds).milliseconds(), milliseconds)
  }
  for milliseconds in [-2147483648, -1, 0] {
    try @moonx.ShutdownGrace::from_milliseconds(milliseconds) catch {
      @moonx.ShutdownGraceError::NonPositiveShutdownGrace(milliseconds=actual) => assert_eq(actual, milliseconds)
    } noraise { _ => fail("Nonpositive grace accepted") }
  }
  assert_eq(@moonx.ShutdownGrace::standard().milliseconds(), 5000)
}
