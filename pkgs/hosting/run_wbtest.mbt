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
async test "a probe stop during start skips later start hooks and the command body" {
  let flag = Ref(false)
  let log = []
  let result = builder(@lander_core.AppName::parse("probe-start"), [])
    |> service("a", start=ctx => {
      ctx.lifetime.register_stop_probe(() => if flag.val { Some(Requested) } else { None })
      log.push("a.start")
      flag.val = true
    }, stop=_ => log.push("a.stop"))
    |> service("b", start=_ => log.push("b.start"), stop=_ => log.push("b.stop"))
    |> build(_ => ())
    |> run(_ => log.push("command"))
  @expect.expect(log).to_equal(["a.start", "a.stop"])
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.failures().length()).to_equal(0)
}

///|
async test "a probe stop during started skips later started hooks and the command body" {
  let flag = Ref(false)
  let log = []
  let result = builder(@lander_core.AppName::parse("probe-started"), [])
    |> service("a", start=ctx => {
      ctx.lifetime.register_stop_probe(() => if flag.val { Some(Requested) } else { None })
      log.push("a.start")
    }, started=_ => {
      log.push("a.started")
      flag.val = true
    }, stop=_ => log.push("a.stop"))
    |> service("b", start=_ => log.push("b.start"), started=_ => log.push("b.started"),
      stop=_ => log.push("b.stop"))
    |> build(_ => ())
    |> run(_ => log.push("command"))
  @expect.expect(log).to_equal(["a.start", "b.start", "a.started", "b.stop", "a.stop"])
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.failures().length()).to_equal(0)
}

///|
async test "absorbed cancellation before a start failure stays visible during protected shutdown" {
  let log = []
  ignore(@async.with_timeout_opt(10, () => {
    let result = builder(@lander_core.AppName::parse("absorbed"), [])
      |> service("a", stopping=ctx => {
        @expect.expect(@async.is_being_cancelled()).to_be_false()
        @expect.expect(ctx.cancelled()).to_be_true()
        @expect.expect(ctx.lifetime.stop_reason() is Some(StartFailed(HookFailed(1)))).to_be_true()
        @async.sleep(1)
        log.push("a.stopping")
      })
      |> service("b", start=_ => {
        ignore(@async.handle_cancellation(() => @async.sleep(60000)))
        @expect.expect(@async.is_being_cancelled()).to_be_true()
        log.push("b absorbed")
        raise HookFailed(1)
      })
      |> build(_ => ())
      |> run(_ => fail("command must not run"))
    @expect.expect(result.reason is StartFailed(HookFailed(1))).to_be_true()
    @expect.expect(result.failures().length()).to_equal(1)
    @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  }))
  @expect.expect(log).to_equal(["b absorbed", "a.stopping"])
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
  @expect.expect(result.exit_code().to_int()).to_equal(131)
}

///|
async test "configuration factory failure gives 2 and runs no hook or command" {
  let log = []
  let host : HostBuilder[Unit] = builder(@lander_core.AppName::parse("config"), [])
  let result = host
    |> service("a", start=_ => log.push("start"), stop=_ => log.push("stop"))
    |> build(_ => raise @config.FileNotFound(path="config.toml"))
    |> run(_ => log.push("command"))
  @expect.expect(result.exit_code().to_int()).to_equal(2)
  @expect.expect(result.reason is StartFailed(@config.FileNotFound(path=_))).to_be_true()
  @expect.expect(log).to_equal([])
}

///|
async test "command binding and usage errors give 2 and still stop" {
  for binding in [false, true] {
    let log = []
    let result = builder(@lander_core.AppName::parse("binding"), [])
      |> service("a", stop=_ => log.push("stop"))
      |> build(_ => ())
      |> run(ctx => {
        if binding { let value : String = @config.bind(ctx.config, "missing"); ignore(value) }
        else { raise UsageError("bad argument") }
      })
    @expect.expect(result.exit_code().to_int()).to_equal(2)
    @expect.expect(result.failures().length()).to_equal(1)
    @expect.expect(log).to_equal(["stop"])
  }
}

///|
async test "custom async report replaces the default and receives failures in order with final code" {
  for usage in [false, true] {
    let seen = []
    let mut replaced = 0
    let result = builder(@lander_core.AppName::parse("reports"), [])
      |> error_report((_, _) => replaced += 1)
      |> error_report((error, code) => {
        @async.sleep(1)
        seen.push((report_text(@lander_core.AppName::parse("custom"), error), code.to_int()))
      })
      |> service("a", stop=_ => raise HookFailed(1), stopped=_ => raise HookFailed(2))
      |> build(_ => ())
      |> run(_ => { if usage { raise UsageError("bad option") } else { raise HookFailed(0) } })
    let expected_code = if usage { 2 } else { 1 }
    @expect.expect(result.exit_code().to_int()).to_equal(expected_code)
    @expect.expect(replaced).to_equal(0)
    @expect.expect(seen).to_equal(result.failures().map(error =>
      (report_text(@lander_core.AppName::parse("custom"), error) catch { _ => abort("valid name") }, expected_code)))
  }
}

///|
async test "no report for clean application or signal outcomes including suppressed failures" {
  for code in [0, 1, 2, 3, 130, 143, 131] {
    let mut calls = 0
    let result = builder(@lander_core.AppName::parse("silent"), [])
      |> error_report((_, _) => calls += 1)
      |> build(_ => ())
      |> run(ctx => ctx.lifetime.set_exit_code(ExitCode::from_int(code)))
    @expect.expect(result.exit_code().to_int()).to_equal(code)
    @expect.expect(calls).to_equal(0)
  }
  for signal in [SignalKind::Interrupt, Terminate, Quit] {
    let mut calls = 0
    let result = builder(@lander_core.AppName::parse("signal"), [])
      |> error_report((_, _) => calls += 1)
      |> service("a", stop=ctx => ctx.lifetime.request_stop(Signal(signal), None))
      |> build(_ => ())
      |> run(ctx => { ctx.lifetime.set_exit_code(ExitCode::from_int(3)); raise UsageError("hidden") })
    @expect.expect(result.exit_code()).to_equal(signal.exit_code())
    @expect.expect(calls).to_equal(0)
    @expect.expect(result.failures().length()).to_equal(1)
  }
}

///|
async test "application code uses chronological order across the first request and stop phase" {
  for set_after in [false, true] {
    let result = builder(@lander_core.AppName::parse("order"), [])
      |> service("a", stop=ctx => {
        if set_after { ctx.lifetime.set_exit_code(ExitCode::from_int(5)) }
        ctx.lifetime.stop_application(exit_code=ExitCode::from_int(9))
      })
      |> build(_ => ())
      |> run(ctx => {
        ctx.lifetime.set_exit_code(ExitCode::from_int(3))
        ctx.lifetime.stop_application(exit_code=ExitCode::from_int(4))
      })
    @expect.expect(result.exit_code().to_int()).to_equal(if set_after { 5 } else { 4 })
  }
}

///|
async test "signal after set_exit_code gives 130" {
  let result = builder(@lander_core.AppName::parse("interrupt"), [])
    |> build(_ => ())
    |> run(ctx => {
      ctx.lifetime.set_exit_code(ExitCode::from_int(3))
      ctx.lifetime.request_stop(Signal(Interrupt), None)
    })
  @expect.expect(result.exit_code().to_int()).to_equal(130)
}

///|
async test "concurrent failing runs can both write their default reports" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("concurrent"), [])
    |> build(_ => ())
  @async.with_task_group(group => {
    let first = group.spawn(() => run(host, _ => raise UsageError("first")))
    let second = group.spawn(() => run(host, _ => raise UsageError("second")))
    @expect.expect(first.wait().exit_code().to_int()).to_equal(2)
    @expect.expect(second.wait().exit_code().to_int()).to_equal(2)
  })
}

///|
async test "custom report also receives a failure before start" {
  let seen = []
  let host : Host[Unit] = builder(@lander_core.AppName::parse("factory-report"), [])
    |> error_report((error, code) => seen.push((error is UsageError("factory"), code)))
    |> build(_ => raise UsageError("factory"))
  let result = run(host, _ => fail("command must not run"))
  @expect.expect(result.exit_code().to_int()).to_equal(2)
  @expect.expect(seen).to_equal([(true, usage_exit_code())])
}

///|
async test "default report preserves the message of fail" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("build"), []) |> build(_ => ())
  let result = run(host, _ => fail("build.invalid_timeout"))
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(result.failures().length()).to_equal(1)
  @expect.expect(report_text(host.name, result.failures()[0]).contains("build.invalid_timeout")).to_be_true()
}
