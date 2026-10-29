///|
fn main raise {
  // The portable policy root builds and runs on all four targets.
  let capacity = @policy.MailboxCapacity::from_int(8)
  assert_true(@policy.MailboxPolicy::Bounded(capacity) != @policy.MailboxPolicy::default())
  assert_eq(@policy.MessageCount::from_int(1).to_int(), 1)
  println("ok")
}
