///|
test "a signal code becomes its kind and any other code is no signal" {
  assert_true(kind_of_code(0) is None)
  assert_true(kind_of_code(1) is Some(Interrupt))
  assert_true(kind_of_code(2) is Some(Terminate))
  assert_true(kind_of_code(3) is Some(Quit))
  assert_true(kind_of_code(4) is None)
  assert_true(kind_of_code(-1) is None)
}

///|
test "the install failure names the signal handlers" {
  assert_eq(
    SignalHandlersUnavailable.message(),
    "The console signal handlers cannot be installed",
  )
}
