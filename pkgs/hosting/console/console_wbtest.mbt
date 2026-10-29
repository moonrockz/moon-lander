///|
test "external readers latch the first signal independently per run" {
  let current : Ref[@hosting.SignalKind?] = Ref(None)
  let probe = @hosting.SignalProbe::new(() => current.val)
  let first = external_signal_reader(probe)
  assert_eq(first(), None)
  current.val = Some(Interrupt)
  assert_eq(first(), Some(Interrupt))
  current.val = None
  assert_eq(first(), Some(Interrupt))
  let second = external_signal_reader(probe)
  assert_eq(second(), None)
  current.val = Some(Terminate)
  assert_eq(first(), Some(Interrupt))
  assert_eq(second(), Some(Terminate))
}

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
  assert_eq(code.to_int(), 7)
  assert_eq(finish(@hosting.ExitCode::from_int(4), None, () => None).to_int(), 4)
}

///|
async test "a signal while the finalizer runs selects the signal code" {
  let code = finish(@hosting.ExitCode::success(), Some(selected => selected), () => Some(
    Terminate,
  ))
  assert_eq(code.to_int(), 143)
}

///|
async test "an external signal first observed during finalization selects its code" {
  let current : Ref[@hosting.SignalKind?] = Ref(None)
  let read = external_signal_reader(@hosting.SignalProbe::new(() => current.val))
  assert_eq(read(), None)
  let code = finish(@hosting.ExitCode::success(), Some(selected => {
    current.val = Some(Terminate)
    @async.pause()
    selected
  }), read)
  assert_eq(code.to_int(), 143)
  current.val = None
  assert_eq(read(), Some(Terminate))
}

///|
async test "a finalizer that raises keeps a failure code and fails a success" {
  let failing : Finalizer = _ => fail("drain failed")
  assert_eq(finish(@hosting.ExitCode::success(), Some(failing), () => None).to_int(), 1)
  assert_eq(
    finish(@hosting.ExitCode::from_int(2), Some(failing), () => None).to_int(),
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

///|
async test "completion follows finalization and sees its selected code" {
  let host = @hosting.builder(@lander_core.AppName::parse("completion"), []) |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, _ => ())
  let order = []
  let code = finish(outcome.exit_code(), Some(_ => {
    order.push("finalized")
    @hosting.ExitCode::from_int(7)
  }), () => None)
  let selected = report_completion(outcome, code, Some((actual, selected) => {
    assert_true(actual.stop_reason() is Completed)
    assert_eq(selected.to_int(), 7)
    order.push("completed")
  }), () => None)
  assert_eq(selected.to_int(), 7)
  assert_eq(order, ["finalized", "completed"])
}

///|
async test "completion failure changes only selected success and runs once" {
  let host = @hosting.builder(@lander_core.AppName::parse("completion"), []) |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, _ => ())
  for value in [0, 2, 130, 143] {
    let calls = Ref(0)
    let selected = report_completion(outcome, @hosting.ExitCode::from_int(value), Some((_, _) => {
      calls.val += 1
      fail("report failed")
    }), () => None)
    assert_eq(calls.val, 1)
    assert_eq(selected.to_int(), if value == 0 { 1 } else { value })
  }
}

///|
async test "a signal during completion wins without rewriting the outcome" {
  let host = @hosting.builder(@lander_core.AppName::parse("completion"), []) |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, _ => ())
  let pending : Ref[@hosting.SignalKind?] = Ref(None)
  let code = report_completion(outcome, outcome.exit_code(), Some((actual, selected) => {
    assert_true(actual.stop_reason() is Completed)
    assert_eq(selected.to_int(), 0)
    pending.val = Some(Terminate)
    @async.pause()
  }), () => pending.val)
  assert_eq(code.to_int(), 143)
  assert_true(outcome.stop_reason() is Completed)
}

///|
async test "completion waits for its output under enclosing task cancellation" {
  let host = @hosting.builder(@lander_core.AppName::parse("completion"), []) |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, _ => ())
  let started : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
  let release : @async.Queue[Unit] = @async.Queue(kind=Unbounded)
  let done = []
  @async.with_task_group(group => {
    let task = group.spawn(allow_failure=true, () => {
      ignore(report_completion(outcome, outcome.exit_code(), Some((_, _) => {
        started.put(())
        release.get()
        done.push("flushed")
      }), () => None))
    })
    started.get()
    task.cancel()
    release.put(())
  })
  assert_eq(done, ["flushed"])
}
