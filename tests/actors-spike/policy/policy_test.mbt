///|
/// The input and rule of a failed count constructor, or `None` when it succeeds.
fn count_failure(make : () -> Unit raise @policy.CountError) -> (Int, String)? {
  try {
    make()
    None
  } catch {
    InvalidCapacity(input~, rule=NotPositive) => Some((input, "capacity"))
    InvalidCount(input~, rule=NotPositive) => Some((input, "count"))
  }
}

///|
/// The input and rule of a failed name parse, or `None` when it parses.
fn name_failure(text : String) -> (String, @policy.NameRule)? {
  try {
    ignore(@policy.ActorName::parse(text))
    None
  } catch {
    InvalidName(input~, rule~) => Some((input, rule))
  }
}

///|
test "capacity and count accept one and the largest Int" {
  assert_eq(@policy.MailboxCapacity::from_int(1).to_int(), 1)
  assert_eq(@policy.MailboxCapacity::from_int(2147483647).to_int(), 2147483647)
  assert_eq(@policy.MessageCount::from_int(1).to_int(), 1)
  assert_eq(@policy.MessageCount::from_int(2147483647).to_int(), 2147483647)
}

///|
test "capacity and count reject zero and negative one with the input" {
  for input in [0, -1] {
    assert_eq(
      count_failure(() => ignore(@policy.MailboxCapacity::from_int(input))),
      Some((input, "capacity")),
    )
    assert_eq(
      count_failure(() => ignore(@policy.MessageCount::from_int(input))),
      Some((input, "count")),
    )
  }
}

///|
test "the default policy is bounded at 128" {
  let policy = @policy.MailboxPolicy::default()
  guard policy is Bounded(capacity) else { fail("default is unbounded") }
  assert_eq(capacity.to_int(), 128)
  assert_true(@policy.MailboxPolicy::Unbounded != policy)
}

///|
test "valid names keep their spelling" {
  let longest = "a".repeat(128)
  for text in ["a", "worker-17", "counter.total", "Snake_case", longest] {
    assert_eq(@policy.ActorName::parse(text).to_string(), text)
  }
}

///|
test "invalid names give the input and the rule" {
  assert_true(name_failure("") is Some(("", Empty)))
  assert_true(name_failure("9counter") is Some(("9counter", FirstNotLetter('9'))))
  assert_true(
    name_failure("counter/total") is Some(("counter/total", InvalidCharacter('/'))),
  )
  assert_true(name_failure("zähler") is Some(("zähler", InvalidCharacter('ä'))))
  assert_true(
    name_failure("two words") is Some(("two words", InvalidCharacter(' '))),
  )
  let long = "a".repeat(129)
  guard name_failure(long) is Some((input, TooLong)) else {
    fail("129 letters did not fail with TooLong")
  }
  assert_eq(input, long)
}

///|
test "names are case sensitive" {
  assert_true(
    @policy.ActorName::parse("Counter") != @policy.ActorName::parse("counter"),
  )
}
