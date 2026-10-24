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
