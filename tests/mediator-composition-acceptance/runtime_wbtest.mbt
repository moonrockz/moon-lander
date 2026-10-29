///|
suberror HandlerFailure { Rejected }

///|
async test "middleware remains open around a genuinely asynchronous reply" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, request) => {
    log.push("handler began")
    started.put(())
    gate.get()
    let reply = delayed_reply(request + 1)
    log.push("handler completed")
    reply
  })
  .use_(@mediator_async.finally_((_, _) => log.push("finally")))
  .use_(@mediator_async.before((_, _) => log.push("before")))
  .use_(@mediator_async.after((_, _, reply) => {
    assert_eq(reply, 42)
    log.push("after")
  }))
  @aio.with_task_group(group => {
    let request = group.spawn(() => sender.send((), 41))
    started.get()
    // The handler has yielded. After and finally must still enclose it.
    assert_eq(log, ["before", "handler began"])
    gate.put(())
    assert_eq(request.wait(), 42)
  })
  log.push("caller returned")
  assert_eq(log, ["before", "handler began", "handler completed", "after", "finally", "caller returned"])
}

///|
async test "an asynchronous handler failure skips after and retains finally" {
  let log = []
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, request) => {
    ignore(delayed_reply(request))
    log.push("handler failed")
    raise Rejected
  })
  .use_(@mediator_async.finally_((_, _) => log.push("finally")))
  .use_(@mediator_async.after((_, _, _) => log.push("after must not run")))
  let failed = try { ignore(sender.send((), 1)); false } catch {
    Rejected => true
    other => raise other
  }
  assert_true(failed)
  assert_eq(log, ["handler failed", "finally"])
}

///|
async test "cancelling a real in-flight send preserves cleanup and skips after" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, request) => {
    defer log.push("handler cleanup")
    started.put(())
    gate.get()
    request
  })
  .use_(@mediator_async.finally_((_, _) => log.push("finally")))
  .use_(@mediator_async.after((_, _, _) => log.push("after must not run")))
  @aio.with_task_group(group => {
    let request = group.spawn(() => sender.send((), 1))
    started.get()
    assert_eq(log, [])
    request.cancel()
  })
  assert_eq(log, ["handler cleanup", "finally"])
}

///|
async test "the existing timeout encloses portable composition without changing its typed error" {
  let log = []
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let limit = @lander_core.TimeLimit::millis(10)
  let sender : @mediator_async.Sender[Unit, Int, Int] = @mediator_async.sender((_, request) => {
    defer log.push("handler cleanup")
    gate.get()
    request
  })
  .use_(@mediator_async.finally_((_, _) => log.push("finally")))
  .use_(@mediator_async.timeout(limit))
  .use_(@mediator_async.after((_, _, _) => log.push("after must not run")))
  let timed_out = try { ignore(sender.send((), 1)); false } catch {
    @mediator.TimedOut(after=actual) => actual == limit
    other => raise other
  }
  assert_true(timed_out)
  assert_eq(log, ["handler cleanup", "finally"])
}
