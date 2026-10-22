///|
test "add gives a new topic and the original topic keeps its handlers" {
  let first : Topic[Unit, String] = topic((_, _) => ())
  let second = first.add((_, _) => ())
  let third = second.add((_, _) => ())
  assert_eq(first.handlers.length(), 1)
  assert_eq(second.handlers.length(), 2)
  assert_eq(third.handlers.length(), 3)
}
