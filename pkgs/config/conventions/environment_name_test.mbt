///|
fn rejected_environment_name(text : String, reason : String) -> Unit raise {
  try {
    ignore(@conventions.EnvironmentName::parse(text))
    fail("expected an invalid environment name")
  } catch {
    @config.InvalidEnvironmentName(name~, reason=actual) => {
      assert_eq(name, text)
      assert_true(actual.contains(reason))
    }
    error => raise error
  }
}

///|
test "an environment name is nonempty but can have one character" {
  rejected_environment_name("", "empty")
  assert_eq(@conventions.EnvironmentName::parse("a").to_string(), "a")
  // Spaces and punctuation have no extra rule in conventions.
  assert_eq(@conventions.EnvironmentName::parse(" ").to_string(), " ")
}

///|
test "only the complete reserved names user and local are rejected in any case" {
  for text in ["user", "User", "uSeR", "USER", "local", "Local", "lOcAl", "LOCAL"] {
    rejected_environment_name(text, "reserved")
  }
  for text in ["users", "locals", "use", "loca", "user-2", "local_2"] {
    assert_eq(@conventions.EnvironmentName::parse(text).to_string(), text)
  }
}

///|
test "slashes backslashes and dots are rejected at any position" {
  for char in ["/", "\\", "."] {
    for text in [char, char + "a", "a" + char, "a" + char + "b"] {
      rejected_environment_name(text, "contains")
    }
  }
  for text in ["-", "_", "a-b", "a_b", "a:b", "staging-2", "Développement"] {
    assert_eq(@conventions.EnvironmentName::parse(text).to_string(), text)
  }
}

///|
test "control character ranges reject their endpoints and accept adjacent characters" {
  for char in ['\u{0}', '\u{1F}', '\u{7F}', '\u{80}', '\u{9F}', '\t', '\n', '\r'] {
    rejected_environment_name("a" + char.to_string() + "b", "control character")
  }
  for char in ['\u{20}', '\u{7E}', '\u{A0}'] {
    let text = "a" + char.to_string() + "b"
    assert_eq(@conventions.EnvironmentName::parse(text).to_string(), text)
  }
}

///|
test "environment names preserve text and equality is exact" {
  let name = @conventions.EnvironmentName::parse("Staging")
  assert_eq(name, @conventions.EnvironmentName::parse(name.to_string()))
  assert_true(name != @conventions.EnvironmentName::parse("staging"))
}

///|
test "parse errors name the input source including a builder default" {
  for source in [Some("--environment"), Some("ACME_ENVIRONMENT"), None] {
    try { ignore(@conventions.EnvironmentName::parse("local", source?)) } catch {
      @config.InvalidEnvironmentName(name~, reason~) => {
        assert_eq(name, "local")
        assert_eq(reason, "the name is reserved (from \{source.unwrap_or("the builder default")})")
      }
      error => raise error
    } noraise { _ => fail("expected InvalidEnvironmentName") }
  }
}
