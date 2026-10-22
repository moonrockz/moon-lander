///|
test "ECMAScript2018 no flags syntax accepts constructs outside matcher subset" {
  for
    pattern in [
      "", "a|", "|a", "(?:)", "()", "^a$", "\\bword\\B", "a*?b+?c??", "a{0}", "a{01,002}?",
      "a{9999999999999999999999999999999999999999,}", "(?=a)*", "(?!a)?", "(?<=a)b",
      "(?<!a)b", "(a)\\1", "\\2(a)", "(?<name>a)\\k<name>", "\\k<name>(?<name>a)",
      "(?<π>a)\\k<π>", "(?<\\u0061>a)\\k<a>", "(?<$a_0>a)", "(?<a‌‍>a)", "[]",
      "[^]", "[a-z]", "[-a]", "[a-]", "[\\d-a]", "[a-\\d]", "[\\b-\\x20]", "[\\c_\\c1]",
      "[\\000-\\377]", "[\\8-\\9]", "\\8", "\\1234", "\\x", "\\u", "\\c", "\\c1",
      "\\q", "\\k<free>", "\\u{1}", "\\p{L}", "]}", "a{x}", "{x}", "a{1,x}", "/a/i",
      "a\nb",
    ] {
    assert_true(@schema.check_pattern(pattern) is Ok(_), msg=pattern)
  }
}

///|
test "ECMAScript2018 rejects malformed groups classes ranges and quantifiers" {
  for
    pattern in [
      "(", ")", "[", "[a", "[z-a]", "[\\xFF-\\x00]", "[b-\\141]", "*a", "+", "?",
      "{1}", "a**", "a*+", "a{1}?+", "a{3,2}", "a{999999999999999999999,999999999999999999998}",
      "(?x:a)", "(?i:a)", "(?P<name>a)", "(?<=a)*", "(?<!a)?", "^*", "\\b+", "\\",
      "(?<>a)", "(?<0>a)", "(?<a-b>a)", "(?<a>a)(?<a>b)", "(?<a>a)(?<\\u0061>b)",
      "(?<a>a)\\k<missing>", "(?<a>a)\\k", "(?<a>a)\\k<>", "(?<\\u0030>a)", "(?<💩>a)",
      "(?<a>a)[\\k]",
    ] {
    guard @schema.check_pattern(pattern) is Err(error) else { fail(pattern) }
    assert_eq(error.code(), @json.InvalidSchema, msg=pattern)
    assert_true(
      error.offset() >= 0 && error.offset() <= pattern.length(),
      msg=pattern,
    )
    assert_true(error.message().length() > 0)
  }
}

///|
test "pattern checks bound source length groups and depth without host recursion" {
  let source = String::make(2000, '(') + "a" + String::make(2000, ')')
  assert_true(@schema.check_pattern(source) is Err(_))
  assert_true(
    @schema.check_pattern(source, limits=@json.Limits::unlimited()) is Ok(_),
  )
  for
    (source, limits) in [
      ("abcd", @json.Limits::new(max_source=3)),
      ("()()", @json.Limits::new(max_nodes=1)),
      ("((a))", @json.Limits::new(max_depth=1)),
    ] {
    guard @schema.check_pattern(source, limits~) is Err(error) else {
      fail(source)
    }
    assert_eq(error.code(), @json.LimitExceeded)
  }
}
