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
  assert_eq(selected_exit_code(outcome, None).to_int(), 3)
  assert_eq(selected_exit_code(outcome, Some(Quit)).to_int(), 131)
  assert_eq(selected_exit_code(outcome, Some(Terminate)).to_int(), 143)
}

///|
async test "the finalizer gets the selected code and gives the final code" {
  let seen = []
  let code = finish(@hosting.ExitCode::from_int(2), Some(selected => {
    seen.push(selected.to_int())
    @hosting.ExitCode::from_int(7)
  }), () => None)
  assert_eq(seen, [2])
  assert_eq(code, 7)
  assert_eq(finish(@hosting.ExitCode::from_int(4), None, () => None), 4)
}

///|
async test "a signal while the finalizer runs selects the signal code" {
  let code = finish(@hosting.ExitCode::success(), Some(selected => selected), () => Some(
    Terminate,
  ))
  assert_eq(code, 143)
}

///|
async test "a finalizer that raises keeps a failure code and fails a success" {
  let failing : Finalizer = _ => fail("drain failed")
  assert_eq(finish(@hosting.ExitCode::success(), Some(failing), () => None), 1)
  assert_eq(
    finish(@hosting.ExitCode::from_int(2), Some(failing), () => None),
    2,
  )
}

///|
async test "the finalizer runs protected from cancellation" {
  let finished = []
  @async.with_task_group(group => {
    let task = group.spawn(allow_failure=true, () => {
      ignore(
        finish(@hosting.ExitCode::success(), Some(selected => {
          @async.sleep(50)
          finished.push(true)
          selected
        }), () => None),
      )
    })
    @async.sleep(10)
    task.cancel()
  })
  assert_eq(finished, [true])
}
