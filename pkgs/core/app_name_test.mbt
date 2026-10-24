///|
/// The rule that `text` breaks, or `None` when it parses.
fn broken_rule(text : String) -> @lander_core.AppNameRule? raise {
  try {
    ignore(@lander_core.AppName::parse(text))
    None
  } catch {
    InvalidAppName(text=failed, rule~) => {
      assert_eq(failed, text)
      Some(rule)
    }
  }
}

///|
test "application names start with a letter and use letters, digits, - and _" {
  for text in ["a", "z", "A", "Z", "a0", "a9", "my-tool", "my_tool", "a-1_b"] {
    assert_true(broken_rule(text) is None)
    assert_eq(@lander_core.AppName::parse(text).to_string(), text)
  }
}

///|
test "an empty application name breaks the rule Empty" {
  assert_true(broken_rule("") is Some(Empty))
}

///|
test "the first character must be an ASCII letter" {
  // The characters next to each ASCII letter range, and other allowed name
  // characters that cannot come first.
  for first in ['@', '[', '`', '{', '0', '9', '-', '_', ' ', '.', 'é'] {
    assert_true(broken_rule("\{first}tool") is Some(FirstNotAsciiLetter))
  }
}

///|
test "a later character must be an ASCII letter, a digit, - or _" {
  // The characters next to each allowed range: `/` and `:` around the digits,
  // `,` and `.` around `-`, `^` and `` ` `` around `_`, `@`, `[` and `{`
  // around the letters, and other characters.
  for
    char in [
      '/', ':', ',', '.', '^', '`', '@', '[', '{', ' ', '\\', 'é', '\n', '\u{00A0}',
    ] {
    assert_true(broken_rule("a\{char}b") is Some(CharNotAllowed(found)) && found == char)
  }
}

///|
test "the error message names the text and the rule" {
  let messages = ["", "9tool", "my tool"].map(text => try {
    ignore(@lander_core.AppName::parse(text))
    "ok"
  } catch {
    err => err.message()
  })
  assert_eq(messages, [
    "Invalid application name \"\": the name is empty",
    "Invalid application name \"9tool\": the name must start with an ASCII letter",
    "Invalid application name \"my tool\": the character \" \" is not allowed; use ASCII letters, digits, '-' and '_'",
  ])
}

///|
test "equal texts give equal names" {
  assert_eq(
    @lander_core.AppName::parse("acme"),
    @lander_core.AppName::parse("acme"),
  )
  assert_not_eq(
    @lander_core.AppName::parse("acme"),
    @lander_core.AppName::parse("Acme"),
  )
}
