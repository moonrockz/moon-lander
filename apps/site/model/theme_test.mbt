///|
test "Cycle" {
  // A user with no stored choice is on `system`. Three clicks give light, dark, system.
  let first = @model.next_theme("system")
  let second = @model.next_theme(first)
  let third = @model.next_theme(second)
  assert_eq([first, second, third], ["light", "dark", "system"])
}

///|
test "a stored value that is not a theme counts as system" {
  assert_eq(@model.next_theme(""), "light")
  assert_eq(@model.next_theme("sepia"), "light")
}
