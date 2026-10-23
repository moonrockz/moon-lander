///|
struct Job(String)

///|
suberror JobError {
  Broken(String)
} derive(Debug)

///|
/// An async handler that records its start, waits `wait_ms`, records its end,
/// and gives `done <name>`.
fn job_step(
  log : Array[String],
  name : String,
  wait_ms~ : Int = 10,
  fails~ : Bool = false,
) -> async (Unit, Job) -> Unit {
  (_, ev) => {
    let Job(id) = ev
    log.push(name + " start " + id)
    @aio.sleep(wait_ms)
    log.push(name + " end " + id)
    if fails {
      raise Broken(name)
    }
  }
}

///|
/// A sender whose handler records its start, waits `wait_ms`, records its end
/// and gives `done <id>`.
fn slow_sender(
  log : Array[String],
  wait_ms~ : Int,
) -> @mediator_async.Sender[Unit, Job, String] {
  @mediator_async.sender((_, req) => {
    let Job(id) = req
    log.push("start " + id)
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
  @aio.sleep(20)
  assert_eq(log, ["start a"])
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
  assert_eq(log, ["start a"])
}

///|
async test "a caller cancellation stops a sequential publish at the second handler" {
  let log = []
  let all = @mediator_async.topic(job_step(log, "one", fails=true))
    .add(job_step(log, "two", wait_ms=1000))
    .add(job_step(log, "three"))
  let outcome = @aio.with_timeout_opt(100, () => all.publish((), Job("a")))
  assert_eq(outcome, None)
  @aio.sleep(20)
  assert_eq(log, ["one start a", "one end a", "two start a"])
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
  @aio.sleep(20)
  assert_eq(log, ["one start a", "two start a"])
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
  assert_eq(log, ["two start a", "two end a"])
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
  @aio.sleep(20)
  assert_eq(log, ["start a"])
}

///|
async test "the timeout middleware gives the reply of a step that ends in time" {
  let log = []
  let limited = slow_sender(log, wait_ms=10).use_(@mediator_async.timeout(1000))
  assert_eq(limited.send((), Job("a")), "done a")
  assert_eq(log, ["start a", "end a"])
}

///|
async test "finally runs one time when the caller cancels a send" {
  let log = []
  let hooked = slow_sender(log, wait_ms=1000).use_(
    @mediator_async.finally_((_, _) => log.push("finally")),
  )
  let reply = @aio.with_timeout_opt(50, () => hooked.send((), Job("a")))
  assert_eq(reply, None)
  @aio.sleep(20)
  assert_eq(log, ["start a", "finally"])
}
