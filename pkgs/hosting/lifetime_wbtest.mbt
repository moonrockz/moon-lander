///|
test "events raised twice and nested late handlers still run one time" {
  let lifetime = Lifetime::new()
  let log = []
  lifetime.on_started(() => {
    log.push("started")
    lifetime.on_started(() => log.push("late"))
  })
  for _ in 0..<2 { lifetime.raise_event(Started) }
  lifetime.on_started(() => log.push("after"))
  @expect.expect(log).to_equal(["started", "late", "after"])
}

///|
test "stop probes and repeated requests preserve first request and optional code" {
  for code in [None, Some(ExitCode::from_int(4))] {
    let lifetime = Lifetime::new()
    let flag = Ref(false)
    lifetime.register_stop_probe(() => if flag.val { Some(Requested) } else { None })
    let token = lifetime.stop_token()
    @expect.expect(token.cancelled()).to_be_false()
    lifetime.stop_application(exit_code?=code)
    lifetime.stop_application(exit_code=ExitCode::from_int(7))
    flag.val = true
    @expect.expect(token.cancelled()).to_be_true()
    @expect.expect(lifetime.requested_code).to_equal(code)
    @expect.expect(lifetime.stop_reason() is Some(Requested)).to_be_true()
    try token.check_cancelled() catch {
      StopRequested => ()
    } noraise { _ => fail("expected StopRequested") }
  }
}

///|
test "a registered probe alone requests stop on all targets" {
  let lifetime = Lifetime::new()
  let flag = Ref(false)
  lifetime.register_stop_probe(() => if flag.val { Some(Requested) } else { None })
  let token = lifetime.stop_token()
  @expect.expect(token.cancelled()).to_be_false()
  flag.val = true
  @expect.expect(token.cancelled()).to_be_true()
  @expect.expect(lifetime.stop_reason() is Some(Requested)).to_be_true()
}

///|
test "a signal in the same step preserves the first request and its code" {
  let lifetime = Lifetime::new()
  let code = ExitCode::from_int(4)
  lifetime.stop_application(exit_code=code)
  lifetime.request_stop(Signal(Quit), None)
  @expect.expect(lifetime.request is Some(Requested)).to_be_true()
  @expect.expect(lifetime.stop_reason() is Some(Requested)).to_be_true()
  @expect.expect(lifetime.signal).to_equal(Some(Quit))
  @expect.expect(lifetime.requested_code).to_equal(Some(code))
}
