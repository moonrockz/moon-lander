///|
async test "slow stop is cancelled at the limit and reports after the stopped event" {
  let log = []
  let reports = []
  let limit = @lander_core.TimeLimit::millis(100)
  let began = Ref(0L)
  let elapsed = Ref(0L)
  let result = builder(@lander_core.AppName::parse("slow-stop"), [])
    |> shutdown_timeout(limit)
    |> service("a", stop=_ => log.push("a.stop"), stopped=_ => log.push("a.stopped"))
    |> service("b", stopping=ctx => {
      began.val = @async.now()
      ctx.lifetime.on_stopped(() => log.push("event.stopped"))
    }, stop=_ => {
      defer { elapsed.val = @async.now() - began.val; log.push("b.cancelled") }
      @async.sleep(10000)
      log.push("b.returned")
    }, stopped=_ => log.push("b.stopped"))
    |> error_report((error, code) => {
      log.push("report")
      reports.push((report_text(@lander_core.AppName::parse("slow-stop"), error), code.to_int()))
    })
    |> build(_ => ())
    |> run(_ => ())
  @expect.expect(log).to_equal(["b.cancelled", "event.stopped", "report"])
  @expect.expect(elapsed.val >= 75L && elapsed.val < 2000L).to_be_true()
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(result.timed_out).to_be_true()
  @expect.expect(result.failures().length()).to_equal(1)
  @expect.expect(result.failures()[0] is ShutdownTimedOut(actual) && actual == limit).to_be_true()
  @expect.expect(reports).to_equal([("slow-stop: Shutdown timed out after 100ms", 1)])
  @expect.expect(result.reason is Completed).to_be_true()
}

///|
async test "shutdown cancels hooks in every stop phase" {
  for phase in [Phase::Stopping, Stop, Stopped] {
    let log = []
    let delay : Hook[Unit] = _ => {
      defer log.push("cancelled")
      @async.sleep(10000)
    }
    let result = builder(@lander_core.AppName::parse("budget"), [])
      |> shutdown_timeout(@lander_core.TimeLimit::millis(100))
      |> service("a", stop=_ => log.push("a.stop"), stopped=_ => log.push("a.stopped"))
      |> service("b", stopping=ctx => {
        ctx.lifetime.on_stopped(() => log.push("event.stopped"))
        if phase == Stopping { delay(ctx) }
      }, stop=ctx => {
        if phase == Stop { delay(ctx) }
      }, stopped=ctx => { if phase == Stopped { delay(ctx) } })
      |> error_report((_, _) => ())
      |> build(_ => ())
      |> run(_ => ())
    @expect.expect(log).to_equal(if phase == Stopped {
      ["a.stop", "cancelled", "event.stopped"]
    } else { ["cancelled", "event.stopped"] })
    @expect.expect(result.timed_out).to_be_true()
  }
}

///|
async test "shutdown shares one budget across individually short hooks" {
  let log = []
  let result = builder(@lander_core.AppName::parse("shared-budget"), [])
    |> shutdown_timeout(@lander_core.TimeLimit::millis(100))
    |> service("a", stop=_ => log.push("a.stop"))
    |> service("b", stopping=_ => { @async.sleep(60); log.push("b.stopping") },
      stop=_ => {
        defer log.push("b.stop.defer")
        @async.sleep(60)
        log.push("b.stop")
      })
    |> error_report((_, _) => ())
    |> build(_ => ())
    |> run(ctx => ctx.lifetime.on_stopped(() => log.push("event.stopped")))
  @expect.expect(log).to_equal(["b.stopping", "b.stop.defer", "event.stopped"])
  @expect.expect(result.timed_out).to_be_true()
}

///|
async test "command work and cancellation defers do not spend the shutdown budget" {
  let log = []
  let result = builder(@lander_core.AppName::parse("after-command"), [])
    |> shutdown_timeout(@lander_core.TimeLimit::millis(100))
    |> service("a", stop=_ => { @async.sleep(30); log.push("stop") })
    |> build(_ => ())
    |> run(ctx => {
      defer @async.protect_from_cancel(() => { @async.sleep(120); log.push("defer") })
      @async.sleep(120)
      ctx.lifetime.stop_application()
    })
  @expect.expect(log).to_equal(["defer", "stop"])
  @expect.expect(result.timed_out).to_be_false()
  @expect.expect(result.exit_code()).to_equal(ExitCode::success())
}

///|
async test "outside cancellation preserves all stop hooks and their timeout" {
  for slow in [false, true] {
    let log = []
    ignore(@async.with_timeout_opt(10, () => {
      let result = builder(@lander_core.AppName::parse("outside-timeout"), [])
        |> shutdown_timeout(@lander_core.TimeLimit::millis(100))
        |> service("a", stopping=_ => log.push("a.stopping"),
          stop=_ => log.push("a.stop"), stopped=_ => log.push("a.stopped"))
        |> service("b", stopping=_ => { @async.sleep(10); log.push("b.stopping") },
          stop=_ => {
            defer log.push("b.stop.defer")
            @async.sleep(if slow { 10000 } else { 10 })
            log.push("b.stop")
          }, stopped=_ => log.push("b.stopped"))
        |> error_report((_, _) => { log.push("report"); raise HookFailed(7) })
        |> build(_ => ())
        |> run(ctx => {
          ctx.lifetime.on_stopped(() => log.push("event.stopped"))
          defer log.push("command.defer")
          @async.sleep(10000)
        })
      @expect.expect(result.reason is Requested).to_be_true()
      @expect.expect(result.timed_out).to_equal(slow)
      @expect.expect(result.exit_code()).to_equal(if slow { ExitCode::failure() } else { ExitCode::success() })
      @expect.expect(result.failures().length()).to_equal(if slow { 1 } else { 0 })
      log.push("outcome")
    }))
    @expect.expect(log).to_equal(if slow {
      ["command.defer", "b.stopping", "a.stopping", "b.stop.defer", "event.stopped", "report", "outcome"]
    } else {
      ["command.defer", "b.stopping", "a.stopping", "b.stop", "b.stop.defer", "a.stop", "b.stopped", "a.stopped", "event.stopped", "outcome"]
    })
  }
}

///|
async test "timeout after a terminate signal keeps code 143 and suppresses reports" {
  let log = []
  let result = builder(@lander_core.AppName::parse("signal-timeout"), [])
    |> shutdown_timeout(@lander_core.TimeLimit::millis(20))
    |> service("a", stop=_ => { defer log.push("cancelled"); @async.sleep(10000) })
    |> error_report((_, _) => log.push("must not report"))
    |> build(_ => ())
    |> run(ctx => {
      ctx.lifetime.on_stopped(() => log.push("event.stopped"))
      ctx.lifetime.request_stop(Signal(Terminate), None)
    })
  @expect.expect(result.reason is Signal(Terminate)).to_be_true()
  @expect.expect(result.exit_code().to_int()).to_equal(143)
  @expect.expect(result.timed_out).to_be_true()
  @expect.expect(result.failures().length()).to_equal(1)
  @expect.expect(log).to_equal(["cancelled", "event.stopped"])
}

///|
async test "a signal recorded by the timed out hook still wins" {
  let result = builder(@lander_core.AppName::parse("late-signal"), [])
    |> shutdown_timeout(@lander_core.TimeLimit::millis(20))
    |> service("a", stop=ctx => {
      ctx.lifetime.request_stop(Signal(Terminate), None)
      @async.sleep(10000)
    })
    |> build(_ => ())
    |> run(_ => ())
  @expect.expect(result.reason is Completed).to_be_true()
  @expect.expect(result.signal).to_equal(Some(Terminate))
  @expect.expect(result.exit_code().to_int()).to_equal(143)
  @expect.expect(result.timed_out).to_be_true()
}

///|
async test "a hook that absorbs timeout cancellation cannot run later hooks" {
  for failed in [false, true] {
    let log = []
    let result = builder(@lander_core.AppName::parse("absorbed-timeout"), [])
      |> shutdown_timeout(@lander_core.TimeLimit::millis(20))
      |> service("a", stop=_ => log.push("must not stop"))
      |> service("b", stop=_ => {
        ignore(@async.handle_cancellation(() => @async.sleep(10000)))
        log.push("absorbed")
        if failed { raise UsageError("cleanup usage") }
      })
      |> error_report((error, code) => {
        log.push("report:\{report_text(@lander_core.AppName::parse("absorbed-timeout"), error)}:\{code.to_int()}")
      })
      |> build(_ => ())
      |> run(ctx => ctx.lifetime.on_stopped(() => log.push("event.stopped")))
    @expect.expect(result.timed_out).to_be_true()
    @expect.expect(result.failures().length()).to_equal(if failed { 2 } else { 1 })
    @expect.expect(result.exit_code().to_int()).to_equal(if failed { 2 } else { 1 })
    @expect.expect(log).to_equal(if failed {
      ["absorbed", "event.stopped", "report:absorbed-timeout: cleanup usage:2", "report:absorbed-timeout: Shutdown timed out after 20ms:2"]
    } else {
      ["absorbed", "event.stopped", "report:absorbed-timeout: Shutdown timed out after 20ms:1"]
    })
  }
}
