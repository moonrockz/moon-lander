///|
fn prefix_rule(text : String) -> @lander_core.EnvPrefixRule? raise {
  try {
    ignore(@lander_core.EnvPrefix::parse(text))
    None
  } catch {
    InvalidEnvPrefix(text=found, rule~) => {
      assert_eq(found, text)
      Some(rule)
    }
  }
}

///|
test "prefix boundary rules" {
  for text in ["a", "z", "A", "Z", "_", "_0", "a9", "MY_TOOL"] {
    assert_eq(prefix_rule(text), None)
    assert_eq(@lander_core.EnvPrefix::parse(text).to_string(), text)
  }
  assert_true(prefix_rule("") is Some(Empty))
  for char in ['@', '[', '`', '{', '^', '0', '9', '-', 'é', ' '] {
    assert_true(prefix_rule("\{char}tool") is Some(FirstNotLetterOrUnderscore))
  }
  for char in ['/', ':', '-', '^', '`', '@', '[', '{', ' ', '\\', 'é', '\n'] {
    assert_true(prefix_rule("a\{char}") is Some(CharNotAllowed(found)) && found == char)
  }
}

///|
test "default prefix cannot fail" {
  for (name, expected) in [("my-tool", "MY_TOOL"), ("a-1_b", "A_1_B"), ("Z", "Z")] {
    let prefix = @lander_core.EnvPrefix::from_app_name(@lander_core.AppName::parse(name))
    assert_eq(prefix.to_string(), expected)
    assert_eq(prefix, @lander_core.EnvPrefix::parse(expected))
  }
}

///|
test "prefix errors describe the input and rule" {
  for text in ["", "9A", "A-"] {
    try { ignore(@lander_core.EnvPrefix::parse(text)) } catch {
      error => assert_true(error.message().contains(text.escape()))
    } noraise { _ => fail("expected a prefix error") }
  }
}
