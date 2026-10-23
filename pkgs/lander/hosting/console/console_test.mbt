///|
test "install succeeds and no stop is requested before a signal" {
  assert_true(@console.install())
  assert_false(@console.stop_requested())
  assert_true(@console.signal_kind() is None)
}

///|
test "each signal kind maps to its exit code" {
  assert_eq(@console.Interrupt.exit_code(), 130)
  assert_eq(@console.Terminate.exit_code(), 143)
  assert_eq(@console.Quit.exit_code(), 131)
}
