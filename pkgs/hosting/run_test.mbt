///|
suberror CommandError {
  DiskFull
  Unavailable(String)
} derive(Debug)

///|
/// A host with two services that write each hook call into the services
/// record, an array of events.
fn two_services() -> @hosting.Host[Array[String]] raise {
  @hosting.builder(@lander_core.AppName::parse("acme"), [])
  |> @hosting.service(
    @hosting.ServiceName::parse("db"),
    start=ctx => ctx.services.push("db.start"),
    stop=ctx => ctx.services.push("db.stop"),
  )
  |> @hosting.service(
    @hosting.ServiceName::parse("cache"),
    start=ctx => ctx.services.push("cache.start"),
    stop=ctx => ctx.services.push("cache.stop"),
  )
  |> @hosting.build(_ => [])
}

///|
async test "a clean run starts in order, stops in reverse order and gives 0" {
  let mut events = []
  let outcome = two_services()
    |> @hosting.run(ctx => {
      ctx.services.push("command")
      events = ctx.services
    })
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::success())
  @expect.expect(outcome.failures().length()).to_equal(0)
  @expect.expect(events).to_equal([
    "db.start", "cache.start", "command", "cache.stop", "db.stop",
  ])
}

///|
async test "a failing command still runs the stop hooks and gives 1" {
  let mut events = []
  let outcome = two_services()
    |> @hosting.run(ctx => {
      events = ctx.services
      raise DiskFull
    })
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::failure())
  @expect.expect(outcome.failures().length()).to_equal(1)
  @expect.expect(outcome.failures()[0] is DiskFull).to_equal(true)
  @expect.expect(events).to_equal([
    "db.start", "cache.start", "cache.stop", "db.stop",
  ])
}

///|
async test "the factory runs one time and each hook gets its record" {
  let mut calls = 0
  let seen = []
  let outcome = @hosting.builder(@lander_core.AppName::parse("acme"), [])
    |> @hosting.service(@hosting.ServiceName::parse("a"), start=ctx => seen.push(ctx.services))
    |> @hosting.service(@hosting.ServiceName::parse("b"), stop=ctx => seen.push(ctx.services))
    |> @hosting.build(_ => {
      calls += 1
      Ref(calls)
    })
    |> @hosting.run(ctx => seen.push(ctx.services))
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::success())
  @expect.expect(calls).to_equal(1)
  @expect.expect(seen.length()).to_equal(3)
  @expect.expect(physical_equal(seen[0], seen[1])).to_equal(true)
  @expect.expect(physical_equal(seen[1], seen[2])).to_equal(true)
}

///|
/// A host whose services `a`, `b` and `c` write each hook call into `log`.
/// `fail_start` and `fail_stop` name the services whose hook raises.
fn three_services(
  log : Array[String],
  fail_start? : String,
  fail_stop? : String,
) -> @hosting.Host[Unit] raise {
  let mut builder : @hosting.HostBuilder[Unit] = @hosting.builder(
    @lander_core.AppName::parse("acme"),
    [],
  )
  for name in ["a", "b", "c"] {
    builder = builder
      |> @hosting.service(
        @hosting.ServiceName::parse(name),
        start=_ => {
          log.push("\{name}.start")
          if fail_start == Some(name) {
            raise Unavailable(name)
          }
        },
        stop=_ => {
          log.push("\{name}.stop")
          if fail_stop == Some(name) {
            raise Unavailable(name)
          }
        },
      )
  }
  builder |> @hosting.build(_ => ())
}

///|
async test "a failed start skips the command and stops only the started services" {
  let log = []
  let outcome = three_services(log, fail_start="b")
    |> @hosting.run(_ => log.push("command"))
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::failure())
  @expect.expect(outcome.failures().length()).to_equal(1)
  @expect.expect(outcome.failures()[0] is Unavailable("b")).to_equal(true)
  @expect.expect(log).to_equal(["a.start", "b.start", "a.stop"])
}

///|
async test "a failed stop does not skip the other stop hooks" {
  let log = []
  let outcome = three_services(log, fail_stop="b")
    |> @hosting.run(_ => log.push("command"))
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::failure())
  @expect.expect(outcome.failures().length()).to_equal(1)
  @expect.expect(log).to_equal([
    "a.start", "b.start", "c.start", "command", "c.stop", "b.stop", "a.stop",
  ])
}

///|
async test "a failed factory runs no hook and gives 1" {
  let log = []
  let builder : @hosting.HostBuilder[Unit] = @hosting.builder(
    @lander_core.AppName::parse("acme"),
    [],
  )
  let outcome = builder
    |> @hosting.service(
      @hosting.ServiceName::parse("a"),
      start=_ => log.push("a.start"),
      stop=_ => log.push("a.stop"),
    )
    |> @hosting.build(_ => raise Unavailable("factory"))
    |> @hosting.run(_ => log.push("command"))
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::failure())
  @expect.expect(outcome.failures()[0] is Unavailable("factory")).to_equal(true)
  @expect.expect(log).to_equal([])
}

///|
async test "a service with no start hook still gets its stop hook" {
  let log = []
  let outcome = @hosting.builder(@lander_core.AppName::parse("acme"), [])
    |> @hosting.service(
      @hosting.ServiceName::parse("log"),
      stop=_ => log.push("log.stop"),
    )
    |> @hosting.build(_ => ())
    |> @hosting.run(_ => log.push("command"))
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::success())
  @expect.expect(log).to_equal(["command", "log.stop"])
}

///|
async test "the failures of an outcome are a copy" {
  let outcome = @hosting.builder(@lander_core.AppName::parse("acme"), [])
    |> @hosting.build(_ => ())
    |> @hosting.run(_ => ())
  outcome.failures().push(Failure("added"))
  @expect.expect(outcome.failures().length()).to_equal(0)
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::success())
}

///|
async test "run groups all six hooks by phase and keeps the command state" {
  let log = []
  let mut builder : @hosting.HostBuilder[Ref[Int]] = @hosting.builder(@lander_core.AppName::parse("acme"), [])
  for name in ["a", "b"] {
    builder = builder |> @hosting.service(
      name,
      starting=ctx => log.push("\{name}.starting:\{ctx.services.val}"),
      start=ctx => log.push("\{name}.start:\{ctx.services.val}"),
      started=ctx => log.push("\{name}.started:\{ctx.services.val}"),
      stopping=ctx => log.push("\{name}.stopping:\{ctx.services.val}"),
      stop=ctx => log.push("\{name}.stop:\{ctx.services.val}"),
      stopped=ctx => log.push("\{name}.stopped:\{ctx.services.val}"),
    )
  }
  let outcome = builder |> @hosting.build(_ => Ref(0)) |> @hosting.run(ctx => {
    log.push("command")
    ctx.services.val = 3
  })
  @expect.expect(log).to_equal([
    "a.starting:0", "b.starting:0", "a.start:0", "b.start:0", "a.started:0", "b.started:0",
    "command", "b.stopping:3", "a.stopping:3", "b.stop:3", "a.stop:3", "b.stopped:3", "a.stopped:3",
  ])
  @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::success())
}

///|
async test "run cleans up after starting and started failures and collects stop errors" {
  for fail_starting in [true, false] {
    let log = []
    let outcome = @hosting.builder(@lander_core.AppName::parse("acme"), [])
      |> @hosting.service("a", stopping=_ => log.push("a.stopping"),
        stop=_ => { log.push("a.stop"); raise DiskFull },
        stopped=_ => log.push("a.stopped"))
      |> @hosting.service("b",
        starting=_ => { log.push("b.starting"); if fail_starting { raise Unavailable("starting") } },
        started=_ => { log.push("b.started"); raise Unavailable("started") },
        stopping=_ => log.push("b.stopping"),
        stop=_ => { log.push("b.stop"); raise DiskFull },
        stopped=_ => log.push("b.stopped"))
      |> @hosting.build(_ => ())
      |> @hosting.run(_ => log.push("command"))
    @expect.expect(log).to_equal(if fail_starting {
      ["b.starting", "a.stopping", "a.stop", "a.stopped"]
    } else {
      ["b.starting", "b.started", "b.stopping", "a.stopping", "b.stop", "a.stop", "b.stopped", "a.stopped"]
    })
    @expect.expect(outcome.exit_code()).to_equal(@hosting.ExitCode::failure())
    @expect.expect(outcome.failures().length()).to_equal(if fail_starting { 2 } else { 3 })
  }
}

///|
async test "lifetime events and late registration run once in phase order" {
  let events = []
  let saved : Ref[@hosting.Lifetime?] = Ref(None)
  let host = @hosting.builder(@lander_core.AppName::parse("events"), [])
    |> @hosting.service("events", starting=ctx => {
      saved.val = Some(ctx.lifetime)
      ctx.lifetime.on_started(() => events.push("started"))
      ctx.lifetime.on_stopping(() => {
        events.push("stopping")
        ctx.lifetime.on_stopping(() => events.push("late stopping"))
      })
      ctx.lifetime.on_stopped(() => events.push("stopped"))
    }, stopping=_ => events.push("hook"))
    |> @hosting.build(_ => ())
  for _ in 0..<2 {
    let result = @hosting.run(host, ctx => {
      ctx.lifetime.on_started(() => events.push("late started"))
      events.push("command")
    })
    @expect.expect(result.failures().length()).to_equal(0)
    saved.val.unwrap().on_stopped(() => events.push("late stopped"))
  }
  @expect.expect(events).to_equal([
    "started", "late started", "command", "stopping", "late stopping", "hook", "stopped", "late stopped",
    "started", "late started", "command", "stopping", "late stopping", "hook", "stopped", "late stopped",
  ])
}

///|
async test "command stop and repeated requests keep the first code and reason" {
  let reasons = []
  let host = @hosting.builder(@lander_core.AppName::parse("stop"), [])
    |> @hosting.service("stop", stopping=ctx => {
      ctx.lifetime.stop_application(exit_code=@hosting.ExitCode::from_int(9))
      reasons.push(ctx.lifetime.stop_reason() is Some(Requested))
    }, stopped=ctx => reasons.push(ctx.lifetime.stop_reason() is Some(Requested)))
    |> @hosting.build(_ => ())
  let result = @hosting.run(host, ctx => {
    ctx.lifetime.stop_application(exit_code=@hosting.ExitCode::from_int(4))
    ctx.lifetime.stop_application(exit_code=@hosting.ExitCode::from_int(5))
    @expect.expect(ctx.cancelled()).to_be_true()
    @expect.expect(ctx.lifetime.stop_token().cancelled()).to_be_true()
  })
  @expect.expect(result.exit_code().to_int()).to_equal(4)
  @expect.expect(result.failures().length()).to_equal(0)
  @expect.expect(reasons).to_equal([true, true])
}

///|
async test "stop during start finishes the hook and skips later starts and command" {
  let events = []
  let result = @hosting.builder(@lander_core.AppName::parse("start"), [])
    |> @hosting.service("a", start=ctx => {
      ctx.lifetime.stop_application()
      @async.sleep(1)
      events.push("a started")
    }, stopping=ctx => {
      @expect.expect(ctx.lifetime.stop_reason() is Some(Requested)).to_be_true()
      events.push("a stopping")
    })
    |> @hosting.service("b", start=_ => events.push("b"))
    |> @hosting.build(_ => ())
    |> @hosting.run(_ => events.push("command"))
  @expect.expect(events).to_equal(["a started", "a stopping"])
  @expect.expect(result.exit_code().to_int()).to_equal(0)
}

///|
async test "started handler can stop before the command" {
  let events = []
  let result = @hosting.builder(@lander_core.AppName::parse("event"), [])
    |> @hosting.service("a", start=ctx => ctx.lifetime.on_started(() => ctx.lifetime.stop_application()),
      stop=_ => events.push("stop"))
    |> @hosting.build(_ => ())
    |> @hosting.run(_ => events.push("command"))
  @expect.expect(events).to_equal(["stop"])
  @expect.expect(result.exit_code().to_int()).to_equal(0)
}

///|
async test "a request after command failure preserves Failed for every stop hook" {
  let reasons = []
  let result = @hosting.builder(@lander_core.AppName::parse("failed"), [])
    |> @hosting.service("a", stopping=ctx => {
      reasons.push(ctx.lifetime.stop_reason() is Some(Failed(DiskFull)))
      ctx.lifetime.stop_application()
    }, stop=ctx => reasons.push(ctx.lifetime.stop_reason() is Some(Failed(DiskFull))),
      stopped=ctx => reasons.push(ctx.lifetime.stop_reason() is Some(Failed(DiskFull))))
    |> @hosting.build(_ => ())
    |> @hosting.run(_ => raise DiskFull)
  @expect.expect(reasons).to_equal([true, true, true])
  @expect.expect(result.exit_code().to_int()).to_equal(1)
  @expect.expect(result.failures().length()).to_equal(1)
}

///|
async test "command polls context and token checks after an event handler asks to stop" {
  for use_token in [false, true] {
    let result = @hosting.builder(@lander_core.AppName::parse("poll"), [])
      |> @hosting.build(_ => ())
      |> @hosting.run(ctx => {
        @expect.expect(ctx.cancelled()).to_be_false()
        ctx.lifetime.on_started(() => ctx.lifetime.stop_application())
        if use_token { ctx.lifetime.stop_token().check_cancelled() }
        else { ctx.check_cancelled() }
        fail("check must raise")
      })
    @expect.expect(result.exit_code().to_int()).to_equal(0)
    @expect.expect(result.failures().length()).to_equal(0)
  }
}

///|
async test "stop cancels a sleeping command and finishes defers before stopping" {
  let events = []
  @async.with_task_group(group => {
    let result = @hosting.builder(@lander_core.AppName::parse("wait"), [])
      |> @hosting.service("a", stopping=ctx => {
        @expect.expect(ctx.lifetime.stop_reason() is Some(Requested)).to_be_true()
        @async.sleep(1)
        events.push("stopping")
      })
      |> @hosting.build(_ => ())
      |> @hosting.run(ctx => {
        defer events.push("defer")
        group.spawn_bg(() => {
          @async.sleep(5)
          ctx.lifetime.stop_application()
        })
        events.push("sleep")
        @async.sleep(60000)
        events.push("unexpected wake")
      })
    @expect.expect(result.exit_code().to_int()).to_equal(0)
    @expect.expect(result.failures().length()).to_equal(0)
  })
  @expect.expect(events).to_equal(["sleep", "defer", "stopping"])
}

///|
async test "stopping flushes all three records from the command services record" {
  let flushed = []
  let result = @hosting.builder(@lander_core.AppName::parse("buffer"), [])
    |> @hosting.service("buffer", stopping=(ctx : @hosting.Context[Array[String]]) => {
      @expect.expect(ctx.lifetime.stop_reason() is Some(Completed)).to_be_true()
      for record in ctx.services { flushed.push(record) }
      ctx.services.clear()
    })
    |> @hosting.build(_ => [])
    |> @hosting.run(ctx => {
      for record in ["one", "two", "three"] { ctx.services.push(record) }
      ctx.lifetime.on_stopped(() => assert_eq(ctx.services.length(), 0) catch { _ => abort("buffer not flushed") })
    })
  @expect.expect(flushed).to_equal(["one", "two", "three"])
  @expect.expect(result.exit_code().to_int()).to_equal(0)
}

///|
async test "set_exit_code gives the application code after a clean command" {
  let result = @hosting.builder(@lander_core.AppName::parse("code"), [])
    |> @hosting.build(_ => ())
    |> @hosting.run(ctx => ctx.lifetime.set_exit_code(@hosting.ExitCode::from_int(7)))
  @expect.expect(result.exit_code().to_int()).to_equal(7)
}

///|
async test "a report writer gets the default report lines instead of standard error" {
  let lines = []
  let host = @hosting.builder(@lander_core.AppName::parse("acme"), [])
    |> @hosting.build(_ => ())
    |> @hosting.report_writer(line => lines.push(line))
  let outcome = @hosting.run(host, _ => raise @hosting.UsageError("bad option"))
  assert_eq(outcome.exit_code().to_int(), 2)
  assert_eq(lines, ["acme: bad option"])
}

///|
async test "an application report keeps its behavior with a report writer" {
  let lines = []
  let reported = []
  let host = @hosting.builder(@lander_core.AppName::parse("acme"), [])
    |> @hosting.error_report((error, code) => reported.push(
      (error is DiskFull, code.to_int()),
    ))
    |> @hosting.build(_ => ())
    |> @hosting.report_writer(line => lines.push(line))
  ignore(@hosting.run(host, _ => raise DiskFull))
  assert_eq(lines, [])
  assert_eq(reported, [(true, 1)])
}
