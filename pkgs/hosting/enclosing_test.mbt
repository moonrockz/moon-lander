///|
suberror EnclosingFailure { Broken } derive(Debug)

///|
async test "a public embedder request cancels an active command and preserves cleanup" {
  for code in [None, Some(@hosting.ExitCode::from_int(7))] {
    let log = []
    let reasons : Array[@hosting.StopReason?] = []
    let ready : @async.Queue[@hosting.Lifetime] = @async.Queue(kind=Unbounded)
    let mut builder : @hosting.HostBuilder[Unit] = @hosting.builder(
      @lander_core.AppName::parse("embedded"), [],
    )
    for name in ["a", "b"] {
      builder = builder |> @hosting.service(
        @hosting.ServiceName::parse(name),
        start=_ => log.push(name + ".start"),
        stopping=ctx => {
          log.push(name + ".stopping")
          reasons.push(ctx.lifetime.stop_reason())
        },
        stop=_ => log.push(name + ".stop"),
        stopped=_ => log.push(name + ".stopped"),
      )
    }
    let host = builder |> @hosting.build(_ => ())
    let outcome = @async.with_task_group(group => {
      let run = group.spawn(() => @hosting.run(host, ctx => {
        defer log.push("command.defer")
        ready.put(ctx.lifetime)
        @async.sleep(60000)
        fail("an embedder request must cancel the active command")
      }))
      let lifetime = ready.get()
      lifetime.stop_from_embedder(exit_code?=code)
      lifetime.stop_application(exit_code=@hosting.ExitCode::from_int(9))
      lifetime.stop_from_embedder()
      run.wait()
    })
    assert_true(outcome.stop_reason() is Embedder)
    assert_eq(outcome.exit_code(), code.unwrap_or(@hosting.ExitCode::success()))
    assert_eq(outcome.failures().length(), 0)
    assert_eq(reasons.length(), 2)
    assert_true(reasons.iter().all(reason => reason is Some(Embedder)))
    assert_eq(log, [
      "a.start", "b.start", "command.defer", "b.stopping", "a.stopping",
      "b.stop", "a.stop", "b.stopped", "a.stopped",
    ])
  }
}

///|
async test "a later embedder request preserves the first requested reason" {
  let host = @hosting.builder(@lander_core.AppName::parse("requested"), [])
    |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, ctx => {
    ctx.lifetime.stop_application()
    ctx.lifetime.stop_from_embedder()
  })
  assert_true(outcome.stop_reason() is Requested)
  assert_eq(outcome.exit_code(), @hosting.ExitCode::success())
}

///|
async test "an embedder request in shutdown preserves an earlier command failure" {
  let seen : Array[@hosting.StopReason?] = []
  let host = @hosting.builder(@lander_core.AppName::parse("failed"), [])
    |> @hosting.service(@hosting.ServiceName::parse("owner"), stopping=ctx => {
      ctx.lifetime.stop_from_embedder()
      seen.push(ctx.lifetime.stop_reason())
    })
    |> @hosting.build(_ => ())
  let outcome = @hosting.run(host, _ => raise Broken)
  assert_true(outcome.stop_reason() is Failed(Broken))
  assert_true(seen[0] is Some(Failed(Broken)))
  assert_eq(outcome.failures().length(), 1)
  assert_eq(outcome.exit_code(), @hosting.ExitCode::failure())
}
