///|
async test "the watcher changes a probed signal into a stop that cancels a waiting command" {
  let signal : Ref[SignalKind?] = Ref(None)
  let log = []
  let result = builder(@lander_core.AppName::parse("signals"), [])
    |> service("a", start=_ => log.push("a.start"), stopping=ctx => {
      log.push("a.stopping")
      @expect.expect(ctx.lifetime.stop_reason() is Some(Signal(Terminate))).to_be_true()
    }, stop=_ => log.push("a.stop"))
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => signal.val), _ => {
      defer log.push("command.defer")
      signal.val = Some(Terminate)
      @async.sleep(10000)
      log.push("command must be cancelled")
    })
  @expect.expect(log).to_equal(["a.start", "command.defer", "a.stopping", "a.stop"])
  @expect.expect(result.reason is Signal(Terminate)).to_be_true()
  @expect.expect(result.signal).to_equal(Some(Terminate))
  @expect.expect(result.exit_code().to_int()).to_equal(143)
  @expect.expect(result.failures().length()).to_equal(0)
}

///|
async test "a synchronous check reads the probe without the watcher" {
  let signal : Ref[SignalKind?] = Ref(None)
  let result = builder(@lander_core.AppName::parse("signals"), [])
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => signal.val), ctx => {
      @expect.expect(ctx.cancelled()).to_be_false()
      signal.val = Some(Interrupt)
      // No suspension point between the signal and the check.
      @expect.expect(ctx.cancelled()).to_be_true()
    })
  @expect.expect(result.reason is Signal(Interrupt)).to_be_true()
  @expect.expect(result.exit_code().to_int()).to_equal(130)
}

///|
async test "a signal wins over the application code" {
  let signal : Ref[SignalKind?] = Ref(None)
  let result = builder(@lander_core.AppName::parse("signals"), [])
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => signal.val), ctx => {
      ctx.lifetime.set_exit_code(ExitCode::from_int(3))
      signal.val = Some(Quit)
      @async.sleep(10000)
    })
  @expect.expect(result.exit_code().to_int()).to_equal(131)
}

///|
async test "a signal during the start phase lets the hook end and stops started services" {
  let signal : Ref[SignalKind?] = Ref(None)
  let log = []
  let result = builder(@lander_core.AppName::parse("signals"), [])
    |> service("a", start=_ => {
      signal.val = Some(Interrupt)
      @async.sleep(120)
      log.push("a.start")
    }, stop=_ => log.push("a.stop"))
    |> service("b", start=_ => log.push("b.start"), stop=_ => log.push("b.stop"))
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => signal.val), _ => log.push("command"))
  @expect.expect(log).to_equal(["a.start", "a.stop"])
  @expect.expect(result.reason is Signal(Interrupt)).to_be_true()
}

///|
async test "the watcher ends with the run" {
  let reads = Ref(0)
  let result = builder(@lander_core.AppName::parse("signals"), [])
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => { reads.val += 1; None }), _ => @async.sleep(120))
  @expect.expect(result.exit_code()).to_equal(ExitCode::success())
  let after_run = reads.val
  @expect.expect(after_run > 0).to_be_true()
  @async.sleep(200)
  @expect.expect(reads.val).to_equal(after_run)
}

///|
async test "a signal before the first hook runs no start hook and gives its code" {
  let log = []
  let result = builder(@lander_core.AppName::parse("signals"), [])
    |> service("a", start=_ => log.push("a.start"), stop=_ => log.push("a.stop"))
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => Some(Interrupt)), _ => log.push("command"))
  @expect.expect(log).to_equal([])
  @expect.expect(result.reason is Signal(Interrupt)).to_be_true()
  @expect.expect(result.exit_code().to_int()).to_equal(130)
}

///|
async test "a signal wins over a failure before the engine starts" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("signals"), [])
    |> build(_ => raise HookFailed(0))
  let result = host
    |> run(signals=SignalProbe::new(() => Some(Terminate)), _ => fail("command must not run"))
  @expect.expect(result.reason is StartFailed(HookFailed(0))).to_be_true()
  @expect.expect(result.exit_code().to_int()).to_equal(143)
}
