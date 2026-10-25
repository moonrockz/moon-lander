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

///|
async test "a signal after the last probe read selects the signal exit code" {
  let host : @hosting.Host[Unit] = @lander_core.AppName::parse("console")
    |> @hosting.builder([])
    |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, ctx => ctx.lifetime.set_exit_code(@hosting.ExitCode::from_int(3)))
  assert_eq(process_exit_code(outcome, None), 3)
  assert_eq(process_exit_code(outcome, Some(Quit)), 131)
  assert_eq(process_exit_code(outcome, Some(Terminate)), 143)
}
