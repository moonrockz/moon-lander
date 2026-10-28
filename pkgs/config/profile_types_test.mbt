///|
fn reject_profile(text : String, rule : @config.ProfileRule) -> Unit raise {
  try { ignore(@config.ProfileName::parse(text)) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.input(), text)
      assert_eq(failure.rule(), rule)
    }
    error => raise error
  } noraise { _ => fail("expected a profile name failure") }
}

///|
test "profile name limits and ASCII grammar are exact" {
  reject_profile("", NameLength(0))
  assert_eq(@config.ProfileName::parse("a").to_string(), "a")
  let longest = Array::make(64, "a").join("")
  assert_eq(@config.ProfileName::parse(longest).to_string(), longest)
  reject_profile(longest + "a", NameLength(65))
  for text in ["0a", "_a", "-a", "A", "é", " a", "`a", "{a", "\u{00a0}a"] {
    reject_profile(text, NameStart)
  }
  for text in ["aA", "a/", "a.", "a\\", "a ", "aé", "a\n", "a\u{7f}", "a:", "a{"] {
    reject_profile(text, NameCharacter)
  }
  for text in ["a0", "a9", "a", "z", "az", "a-", "a_", "local", "user", "default"] {
    assert_eq(@config.ProfileName::parse(text).to_string(), text)
  }
}

///|
test "profile CSV uses ASCII trim and rejects empty elements" {
  let names = @config.ProfileNames::parse_csv(" \tpostgres,metrics\r\n")
  assert_eq(names.names().map(name => name.to_string()), ["postgres", "metrics"])
  for text in ["", " ", ",a", "a,", "a,,b"] {
    try { ignore(@config.ProfileNames::parse_csv(text)) } catch {
      @config.Profile(failure~) => assert_eq(failure.rule(), EmptyElement)
      error => raise error
    } noraise { _ => fail("expected an empty CSV element failure") }
  }
  assert_eq(@config.ProfileSelection::from_variable(" \t\r\n", variable="ACME_PROFILES"), Disabled)
  assert_eq(@config.ProfileSelection::from_variable("metrics", variable="ACME_PROFILES"), Selected(@config.ProfileNames::new([@config.ProfileName::parse("metrics")])))
}

///|
test "returned names and reasons cannot mutate retained profile state" {
  let name = @config.ProfileName::parse("metrics")
  let input = [name]
  let names = @config.ProfileNames::new(input)
  input.clear()
  let resolution = @config.ProfileResolution::new(Discovery, names, names, reasons=[Root(name, Discovery)])
  names.names().clear()
  resolution.reasons().clear()
  assert_true(resolution.contains(name))
  assert_eq(resolution.reasons().length(), 1)
  assert_true(@config.ProfileState::Resolved(resolution).contains(name))
  assert_false(@config.ProfileState::Off.contains(name))
}

///|
test "resolved active names keep the last occurrence and enforce the exact limit" {
  let names = Array::makei(128, index => @config.ProfileName::parse("p\{index}"))
  let roots = @config.ProfileNames::new(names)
  let exact = @config.ProfileResolution::new(Discovery, roots, roots)
  assert_eq(exact.active().names().length(), 128)
  let excess = @config.ProfileNames::new([..names, @config.ProfileName::parse("extra")])
  try { ignore(@config.ProfileResolution::new(Discovery, excess, excess)) } catch {
    @config.Profile(failure~) => assert_eq(failure.rule(), ActiveLimit(129))
    error => raise error
  } noraise { _ => fail("expected the active-name limit") }
  let a = @config.ProfileName::parse("a")
  let b = @config.ProfileName::parse("b")
  let repeat = @config.ProfileNames::new([a,b,a])
  assert_eq(@config.ProfileResolution::new(Discovery, repeat, repeat).active().names(), [b,a])
}

///|
test "disabled resolution clears roots reasons and interpreted controls" {
  let name = @config.ProfileName::parse("metrics")
  let names = @config.ProfileNames::new([name])
  let resolution = @config.ProfileResolution::new(Discovery, names, names, disabled=true, reasons=[Root(name, Discovery)], controls=[Policy])
  assert_eq(resolution.active().names(), [])
  assert_eq(resolution.roots().names(), [])
  assert_eq(resolution.reasons(), [])
  assert_eq(resolution.controls(), [])
}
