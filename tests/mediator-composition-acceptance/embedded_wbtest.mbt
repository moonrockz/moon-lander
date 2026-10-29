///|
/// Exercise the same async sender inside the framework's actual embed driver.
test "the public async sender completes within the embedded driver without an event loop" {
  let log = []
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, request) => {
    log.push("handler")
    request + 1
  })
  .use_(@mediator_async.finally_((_, _) => log.push("finally")))
  .use_(@mediator_async.before((_, _) => log.push("before")))
  .use_(@mediator_async.after((_, _, reply) => {
    assert_eq(reply, 42)
    log.push("after")
  }))
  let host = @hosting.builder(@lander_core.AppName::parse("portable-sender"), [])
    |> @hosting.build(_ => sender)
  let reply : Ref[Int?] = Ref(None)
  let outcome = @hosting.run_embedded(host, ctx => {
    reply.val = Some(ctx.services.send((), 41))
    log.push("command returned")
  })
  assert_eq(outcome.exit_code().to_int(), 0)
  assert_true(outcome.stop_reason() is Completed)
  assert_eq(reply.val, Some(42))
  assert_eq(log, ["before", "handler", "after", "finally", "command returned"])
}

///|
suberror EmbeddedFailure { Rejected }

///|
test "an embedded async handler failure retains its cause and finally" {
  let log = []
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, _) => raise Rejected)
    .use_(@mediator_async.finally_((_, _) => log.push("finally")))
    .use_(@mediator_async.after((_, _, _) => log.push("after must not run")))
  let host = @hosting.builder(@lander_core.AppName::parse("embedded-failure"), [])
    |> @hosting.error_report((_, _) => ())
    |> @hosting.build(_ => sender)
  let outcome = @hosting.run_embedded(host, ctx => ignore(ctx.services.send((), 1)))
  assert_eq(outcome.exit_code().to_int(), 1)
  assert_true(outcome.stop_reason() is Failed(Rejected))
  assert_eq(log, ["finally"])
}

///|
/// Test-only actual suspension, matching the embedded driver's own fixture.
async fn suspend_here(register : ((Unit) -> Unit) -> Unit) -> Unit noraise + nocancel = "%async.suspend"

///|
test "a suspending embedded send stays a typed failure after late completion" {
  let held : Array[() -> Unit] = []
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, request) => {
    suspend_here(wake => held.push(() => wake(())))
    request
  })
  let host = @hosting.builder(@lander_core.AppName::parse("embedded-suspension"), [])
    |> @hosting.error_report((_, _) => ())
    |> @hosting.build(_ => sender)
  let outcome = @hosting.run_embedded(host, ctx => ignore(ctx.services.send((), 1)))
  assert_eq(outcome.exit_code().to_int(), 1)
  assert_true(outcome.failures() is [@hosting.CommandSuspended])
  assert_eq(held.length(), 1)
  held[0]()
  assert_eq(outcome.exit_code().to_int(), 1)
  assert_true(outcome.failures() is [@hosting.CommandSuspended])
}
