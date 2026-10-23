///|
struct Job(String)

///|
suberror JobError {
  Broken(String)
} derive(Debug)

///|
/// An async handler that records its start, waits `wait_ms`, records its end,
/// and raises `Broken(name)` when `fails` is true. A `defer` records
/// `stopped` when the handler ends in any way, also by a cancellation.
fn job_step(
  log : Array[String],
  name : String,
  wait_ms~ : Int = 10,
  fails~ : Bool = false,
) -> async (Unit, Job) -> Unit {
  (_, ev) => {
    let Job(id) = ev
    log.push(name + " start " + id)
    defer log.push(name + " stopped " + id)
    @aio.sleep(wait_ms)
    log.push(name + " end " + id)
    if fails {
      raise Broken(name)
    }
  }
}

///|
/// A sender whose handler records its start, waits `wait_ms`, records its end
/// and gives `done <id>`. A `defer` records `stopped` when the handler ends.
fn slow_sender(
  log : Array[String],
  wait_ms~ : Int,
) -> @mediator_async.Sender[Unit, Job, String] {
  @mediator_async.sender((_, req) => {
    let Job(id) = req
    log.push("start " + id)
    defer log.push("stopped " + id)
    @aio.sleep(wait_ms)
    log.push("end " + id)
    "done " + id
  })
}

///|
async test "a caller cancellation stops send with no reply and no error" {
  let log = []
  let reply = @aio.with_timeout_opt(50, () => {
    slow_sender(log, wait_ms=1000).send((), Job("a"))
  })
  assert_eq(reply, None)
  assert_eq(log, ["start a", "stopped a"])
  @aio.sleep(20)
  assert_eq(log, ["start a", "stopped a"])
}

///|
async test "a middleware that catches every error does not catch a cancellation" {
  let log = []
  let guarded = slow_sender(log, wait_ms=1000).use_(
    @mediator_async.middleware((next, ctx, req) => {
      next(ctx, req) catch {
        _ => "caught"
      }
    }),
  )
  let reply = @aio.with_timeout_opt(50, () => guarded.send((), Job("a")))
  assert_eq(reply, None)
  assert_eq(log, ["start a", "stopped a"])
}

///|
async test "a caller cancellation stops a sequential publish at the second handler" {
  let log = []
  let all = @mediator_async.topic(job_step(log, "one", fails=true))
    .add(job_step(log, "two", wait_ms=1000))
    .add(job_step(log, "three"))
  let outcome = @aio.with_timeout_opt(100, () => all.publish((), Job("a")))
  assert_eq(outcome, None)
  assert_eq(log, [
    "one start a", "one end a", "one stopped a", "two start a", "two stopped a",
  ])
  @aio.sleep(20)
  assert_eq(log.length(), 5)
}

///|
async test "a caller cancellation stops every handler of a concurrent publish" {
  let log = []
  let all = @mediator_async.topic(job_step(log, "one", wait_ms=1000)).add(
    job_step(log, "two", wait_ms=1000),
  )
  let outcome = @aio.with_timeout_opt(50, () => {
    all.publish_concurrent((), Job("a"))
  })
  assert_eq(outcome, None)
  assert_eq(log[0:2].to_owned(), ["one start a", "two start a"])
  assert_eq(log.filter(line => line.contains("stopped")).length(), 2)
  assert_false(log.iter().any(line => line.contains("end")))
}

///|
async test "a handler timeout passes out of send as an ordinary error" {
  let timed : @mediator_async.Sender[Unit, Job, String] = @mediator_async.sender((
    _,
    _,
  ) => {
    @aio.with_timeout(10, () => @aio.sleep(1000), error=Broken("own limit"))
    "never"
  })
  try timed.send((), Job("a")) catch {
    Broken(text) => assert_eq(text, "own limit")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}

///|
async test "a handler timeout is a publish failure and the other handlers run" {
  let log = []
  let all = @mediator_async.topic((_, _) => {
    @aio.with_timeout(10, () => @aio.sleep(1000))
  }).add(job_step(log, "two"))
  try all.publish((), Job("a")) catch {
    @mediator.PublishFailed(handlers~, failures~) => {
      assert_eq(handlers, 2)
      assert_eq(failures.map(failure => failure.position), [1])
      assert_true(failures[0].error is @aio.TimeoutError)
    }
    other => fail("publish raised another error: \{other}")
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["two start a", "two end a", "two stopped a"])
}

///|
async test "the timeout middleware stops a slow handler and raises TimedOut" {
  let log = []
  let limited = slow_sender(log, wait_ms=1000).use_(@mediator_async.timeout(50))
  try limited.send((), Job("a")) catch {
    @mediator.TimedOut(after_ms~) => assert_eq(after_ms, 50)
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  assert_eq(log, ["start a", "stopped a"])
}

///|
async test "the timeout middleware gives the reply of a step that ends in time" {
  let log = []
  let limited = slow_sender(log, wait_ms=10).use_(@mediator_async.timeout(1000))
  assert_eq(limited.send((), Job("a")), "done a")
  assert_eq(log, ["start a", "end a", "stopped a"])
}

///|
async test "finally runs one time when the caller cancels a send" {
  let log = []
  let hooked = slow_sender(log, wait_ms=1000).use_(
    @mediator_async.finally_((_, _) => log.push("finally")),
  )
  let reply = @aio.with_timeout_opt(50, () => hooked.send((), Job("a")))
  assert_eq(reply, None)
  assert_eq(log, ["start a", "stopped a", "finally"])
}

///|
/// A handler that records its start, and when the caller cancels its wait,
/// runs a protected cleanup that raises an ordinary error.
fn failing_cleanup(log : Array[String]) -> async (Unit, Job) -> Unit {
  (_, _) => {
    log.push("cleanup start")
    defer log.push("cleanup stopped")
    let waited = @aio.handle_cancellation(() => @aio.sleep(1000))
    if waited is None {
      @aio.protect_from_cancel(() => raise Broken("cleanup"))
    }
  }
}

///|
async test "a handler error during a cancellation does not start the next handler" {
  let log = []
  let all = @mediator_async.topic(failing_cleanup(log)).add((_, _) => {
    log.push("next start")
  })
  let outcome = @aio.with_timeout_opt(50, () => all.publish((), Job("a")))
  assert_eq(outcome, None)
  assert_eq(log, ["cleanup start", "cleanup stopped"])
}

///|
async test "handler errors during a cancellation give no concurrent PublishFailed" {
  let log = []
  let all = @mediator_async.topic(failing_cleanup(log)).add(
    failing_cleanup(log),
  )
  let outcome = @aio.with_timeout_opt(50, () => {
    all.publish_concurrent((), Job("a"))
  })
  assert_eq(outcome, None)
  assert_eq(log.filter(line => line == "cleanup stopped").length(), 2)
}

///|
/// A sync send has no loop and no `catch`, so it adds nothing to the outcome
/// of its handler: a handler that turns its own cancellation into an ordinary
/// error, through a protected cleanup, gives that error from `send`, the same
/// as a direct call of the handler.
async test "send gives the cleanup error of a cancelled handler, as a direct call does" {
  let log = []
  let cleanup = failing_cleanup(log)
  let direct = try {
    @aio.with_timeout_opt(50, () => cleanup((), Job("a"))) |> ignore
    "no error"
  } catch {
    Broken(text) => text
    other => "other \{other}"
  }
  let cleanup_sender : @mediator_async.Sender[Unit, Job, Unit] = @mediator_async.sender(
    cleanup,
  )
  let sent = try {
    @aio.with_timeout_opt(50, () => cleanup_sender.send((), Job("a"))) |> ignore
    "no error"
  } catch {
    Broken(text) => text
    other => "other \{other}"
  }
  assert_eq(direct, "cleanup")
  assert_eq(sent, direct)
}
