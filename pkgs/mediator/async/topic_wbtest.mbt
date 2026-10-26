///|
test "add gives a new topic and the original topic keeps its handlers" {
  let first : Topic[Unit, String] = topic((_, _) => ())
  let second = first.add((_, _) => ())
  let third = second.add((_, _) => ())
  assert_true(first.handlers is Own(handlers) && handlers.length() == 1)
  assert_true(second.handlers is Own(handlers) && handlers.length() == 2)
  assert_true(third.handlers is Own(handlers) && handlers.length() == 3)
}
