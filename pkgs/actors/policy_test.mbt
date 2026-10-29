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
