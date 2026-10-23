///|
suberror CommandError {
  DiskFull
} derive(Debug)

///|
/// A host with two services that write each hook call into the services
/// record, an array of events.
fn two_services() -> @hosting.Host[Array[String]] {
  @hosting.builder("acme", [])
  |> @hosting.service(
    "db",
    start=ctx => ctx.services.push("db.start"),
    stop=ctx => ctx.services.push("db.stop"),
  )
  |> @hosting.service(
    "cache",
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
  @expect.expect(outcome.exit_code).to_equal(@hosting.ExitCode(0))
  @expect.expect(outcome.failures.length()).to_equal(0)
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
  @expect.expect(outcome.exit_code).to_equal(@hosting.ExitCode(1))
  @expect.expect(outcome.failures.length()).to_equal(1)
  @expect.expect(outcome.failures[0] is DiskFull).to_equal(true)
  @expect.expect(events).to_equal([
    "db.start", "cache.start", "cache.stop", "db.stop",
  ])
}

///|
async test "the factory runs one time and each hook gets its record" {
  let mut calls = 0
  let seen = []
  let outcome = @hosting.builder("acme", [])
    |> @hosting.service("a", start=ctx => seen.push(ctx.services))
    |> @hosting.service("b", stop=ctx => seen.push(ctx.services))
    |> @hosting.build(_ => {
      calls += 1
      Ref(calls)
    })
    |> @hosting.run(ctx => seen.push(ctx.services))
  @expect.expect(outcome.exit_code).to_equal(@hosting.ExitCode(0))
  @expect.expect(calls).to_equal(1)
  @expect.expect(seen.length()).to_equal(3)
  @expect.expect(physical_equal(seen[0], seen[1])).to_equal(true)
  @expect.expect(physical_equal(seen[1], seen[2])).to_equal(true)
}
