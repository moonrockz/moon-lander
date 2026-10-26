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
  // A wide lower bound: Windows timers can fire about 16 ms early. A timeout
  // that fires at once still fails.
  @expect.expect(elapsed.val >= 50L && elapsed.val < 2000L).to_be_true()
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
  // Each hook is 100 ms below the budget, and together they are 100 ms over
  // it. Both margins are much larger than the timer resolution of a Windows
  // runner (about 16 ms), so the result does not depend on it.
  let log = []
  let result = builder(@lander_core.AppName::parse("shared-budget"), [])
    |> shutdown_timeout(@lander_core.TimeLimit::millis(300))
    |> service("a", stop=_ => log.push("a.stop"))
    |> service("b", stopping=_ => { @async.sleep(200); log.push("b.stopping") },
      stop=_ => {
        defer log.push("b.stop.defer")
        @async.sleep(200)
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
      // The defer alone is 150 ms over the budget, so a budget that started at
      // the stop request would clearly expire.
      defer @async.protect_from_cancel(() => { @async.sleep(250); log.push("defer") })
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
async test "timeout after a terminate signal keeps code 143 and reports the timeout" {
  let log = []
  let reports = []
  let limit = @lander_core.TimeLimit::millis(20)
  let result = builder(@lander_core.AppName::parse("signal-timeout"), [])
    |> shutdown_timeout(limit)
    |> service("a", stop=_ => { defer log.push("cancelled"); @async.sleep(10000) })
    |> error_report((error, code) => {
      log.push("report")
      reports.push((error, code))
    })
    |> build(_ => ())
    |> run(ctx => {
      ctx.lifetime.on_stopped(() => log.push("event.stopped"))
      ctx.lifetime.request_stop(Signal(Terminate), None)
    })
  @expect.expect(result.reason is Signal(Terminate)).to_be_true()
  @expect.expect(result.exit_code().to_int()).to_equal(143)
  @expect.expect(result.timed_out).to_be_true()
  @expect.expect(result.failures().length()).to_equal(1)
  @expect.expect(log).to_equal(["cancelled", "event.stopped", "report"])
  @expect.expect(reports.length()).to_equal(1)
  @expect.expect(reports[0].0 is ShutdownTimedOut(actual) && actual == limit).to_be_true()
  @expect.expect(reports[0].1.to_int()).to_equal(143)
}

///|
async test "outside cancellation during a stop hook preserves the full stop phase" {
  let log = []
  let completed = @async.with_timeout_opt(50, () => {
    let result = builder(@lander_core.AppName::parse("cancel-during-stop"), [])
      |> shutdown_timeout(@lander_core.TimeLimit::millis(1000))
      |> service("a", stop=_ => log.push("a.stop"))
      |> service("b", stop=_ => {
        log.push("b.stop.started")
        @async.sleep(200)
        log.push("b.stop")
      })
      |> build(_ => ())
      |> run(_ => ())
    @expect.expect(result.exit_code()).to_equal(ExitCode::success())
    @expect.expect(result.timed_out).to_be_false()
    @expect.expect(result.failures().length()).to_equal(0)
    log.push("outcome")
  })
  @expect.expect(completed is None).to_be_true()
  @expect.expect(log).to_equal(["b.stop.started", "b.stop", "a.stop", "outcome"])
}

///|
async test "signal codes report only the timeout among multiple failures" {
  for signal in [SignalKind::Interrupt, Terminate, Quit] {
    let reports = []
    let limit = @lander_core.TimeLimit::millis(20)
    let result = builder(@lander_core.AppName::parse("signal-failures"), [])
      |> shutdown_timeout(limit)
      |> service("a", stop=_ => @async.sleep(10000))
      |> error_report((error, code) => reports.push((error, code)))
      |> build(_ => ())
      |> run(ctx => {
        ctx.lifetime.request_stop(Signal(signal), None)
        raise UsageError("command usage")
      })
    @expect.expect(result.failures().length()).to_equal(2)
    @expect.expect(result.exit_code()).to_equal(signal.exit_code())
    @expect.expect(reports.length()).to_equal(1)
    @expect.expect(reports[0].0 is ShutdownTimedOut(actual) && actual == limit).to_be_true()
    @expect.expect(reports[0].1).to_equal(signal.exit_code())
  }
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
