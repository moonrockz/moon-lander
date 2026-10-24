///|
async test "factory failure before start has StartFailed reason" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("test"), [])
    |> build(_ => raise HookFailed(0))
  let result = run(host, _ => fail("command must not run"))
  @expect.expect(result.reason is StartFailed(HookFailed(0))).to_be_true()
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(result.failures().length()).to_equal(1)
}

///|
test "outcome of a failure before the start phase has StartFailed reason" {
  let result = outcome(HookFailed(1))
  @expect.expect(result.reason is StartFailed(HookFailed(1))).to_be_true()
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(result.failures().length()).to_equal(1)
}

///|
async test "request then hook failure retains Requested and does not start the service" {
  let log = []
  let result = builder(@lander_core.AppName::parse("test"), [])
    |> service("a", start=ctx => {
      ctx.lifetime.stop_application()
      raise HookFailed(0)
    }, stop=_ => log.push("must not stop"))
    |> build(_ => ())
    |> run(_ => log.push("must not run"))
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.failures().length()).to_equal(1)
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(log).to_equal([])
}

///|
async test "request after command failure preserves outcome Failed" {
  let result = builder(@lander_core.AppName::parse("test"), [])
    |> service("a", stopping=ctx => ctx.lifetime.stop_application())
    |> build(_ => ())
    |> run(_ => raise HookFailed(0))
  @expect.expect(result.reason is Failed(HookFailed(0))).to_be_true()
}

///|
async test "registered stop probe reaches engine through command check" {
  let flag = Ref(false)
  let result = builder(@lander_core.AppName::parse("probe"), [])
    |> build(_ => ())
    |> run(ctx => {
      ctx.lifetime.register_stop_probe(() => if flag.val { Some(Requested) } else { None })
      @expect.expect(ctx.cancelled()).to_be_false()
      flag.val = true
      ctx.check_cancelled()
      fail("probe must stop")
    })
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.failures().length()).to_equal(0)
}

///|
async test "outside cancellation runs command defers then protected shutdown" {
  let log = []
  let result = @async.with_timeout_opt(10, () => {
    builder(@lander_core.AppName::parse("outside"), [])
    |> service("a", stopping=ctx => {
      @expect.expect(ctx.lifetime.stop_reason() is Some(Requested)).to_be_true()
      @expect.expect(@async.is_being_cancelled()).to_be_false()
      @async.sleep(1)
      log.push("stop")
    })
    |> build(_ => ())
    |> run(ctx => {
      defer {
        @expect.expect(ctx.cancelled()).to_be_true() catch { _ => abort("cancel probe") }
        log.push("defer")
      }
      @async.sleep(60000)
    })
  })
  ignore(result)
  @expect.expect(log).to_equal(["defer", "stop"])
}

///|
async test "StopRequested in a start hook is a stop without marking that service" {
  for phase in [Phase::Starting, Start, Started] {
    for has_start in [false, true] {
      if phase == Start && !has_start { continue }
      let log = []
      let interrupt : Hook[Unit] = ctx => {
        ctx.lifetime.stop_application()
        ctx.check_cancelled()
      }
      let result = builder(@lander_core.AppName::parse("start-stop"), [])
        |> service("a",
          starting?=if phase == Starting { Some(interrupt) } else { None },
          start?=if phase == Start { Some(interrupt) } else if has_start { Some(_ => ()) } else { None },
          started?=if phase == Started { Some(interrupt) } else { None },
          stop=_ => log.push("stop"))
        |> build(_ => ())
        |> run(_ => fail("command must not run"))
      @expect.expect(result.reason is Requested).to_be_true()
      @expect.expect(result.failures().length()).to_equal(0)
      @expect.expect(result.exit_code()).to_equal(ExitCode::success())
      @expect.expect(log).to_equal(if phase == Started { ["stop"] } else { [] })
    }
  }
}

///|
async test "StopRequested in every stop phase does not skip later cleanup" {
  for phase in [Phase::Stopping, Stop, Stopped] {
    let log = []
    let result = builder(@lander_core.AppName::parse("stop-check"), [])
      |> service("a", stopping=_ => log.push("a.stopping"),
        stop=_ => log.push("a.stop"), stopped=_ => log.push("a.stopped"))
      |> service("b", stopping=ctx => {
        log.push("b.stopping")
        if phase == Stopping { ctx.check_cancelled() }
      }, stop=ctx => {
        log.push("b.stop")
        if phase == Stop { ctx.check_cancelled() }
      }, stopped=ctx => {
        log.push("b.stopped")
        if phase == Stopped { ctx.check_cancelled() }
      })
      |> build(_ => ())
      |> run(ctx => ctx.lifetime.stop_application())
    @expect.expect(result.reason is Requested).to_be_true()
    @expect.expect(result.failures().length()).to_equal(0)
    @expect.expect(result.exit_code()).to_equal(ExitCode::success())
    @expect.expect(log).to_equal(["b.stopping", "a.stopping", "b.stop", "a.stop", "b.stopped", "a.stopped"])
  }
}

///|
async test "StopRequested raised directly establishes a requested stop" {
  let result = builder(@lander_core.AppName::parse("direct-stop"), [])
    |> build(_ => ())
    |> run(_ => raise StopRequested::StopRequested)
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.failures().length()).to_equal(0)
  @expect.expect(result.exit_code()).to_equal(ExitCode::success())
}

///|
async test "a signal before the command reply does not replace its first request reason" {
  let result = builder(@lander_core.AppName::parse("signal-stop"), [])
    |> build(_ => ())
    |> run(ctx => {
      ctx.lifetime.stop_application(exit_code=ExitCode::from_int(4))
      ctx.lifetime.request_stop(Signal(Quit), None)
    })
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.signal).to_equal(Some(Quit))
  @expect.expect(result.exit_code().to_int()).to_equal(4)
}
