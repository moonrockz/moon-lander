///|
struct Order(String)

///|
suberror OrderError {
  Rejected(String)
} derive(Debug)

///|
async test "a wrapped core sender runs the core middleware and handler" {
  let log = []
  let core : @mediator.Sender[Unit, Order, String] = @mediator.sender((_, req) => {
    log.push("core handler")
    let Order(id) = req
    "placed " + id
  })
  let logged = core.use_(
    @mediator.middleware((next, ctx, req) => {
      log.push("core log in")
      let reply = next(ctx, req)
      log.push("core log out")
      reply
    }),
  )
  let wrapped = @mediator_async.Sender::from_sync(logged).use_(
    @mediator_async.before((_, _) => {
      @aio.sleep(1)
      log.push("async before")
    }),
  )
  assert_eq(wrapped.send((), Order("a")), "placed a")
  assert_eq(log, ["async before", "core log in", "core handler", "core log out"])
}

///|
async test "a wrapped core sender passes the core error out unchanged" {
  let core : @mediator.Sender[Unit, Order, String] = @mediator.sender((_, req) => {
    let Order(id) = req
    raise Rejected(id)
  })
  try @mediator_async.Sender::from_sync(core).send((), Order("a")) catch {
    Rejected(id) => assert_eq(id, "a")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}

///|
/// A core topic of three handlers whose second handler raises.
fn core_orders(log : Array[String]) -> @mediator.Topic[Unit, Order] {
  @mediator.topic((_, _) => log.push("core one"))
  .add((_, req) => {
    log.push("core two")
    let Order(id) = req
    raise Rejected(id)
  })
  .add((_, _) => log.push("core three"))
}

///|
/// Check that `error` is the core `PublishFailed` of `core_orders`.
fn expect_core_failure(error : Error) -> Unit raise {
  guard error is @mediator.PublishFailed(handlers~, failures~) else {
    fail("publish raised another error: \{error}")
  }
  assert_eq(handlers, 3)
  assert_eq(failures.length(), 1)
  assert_eq(failures.to_array()[0].position, 2)
  assert_true(failures.to_array()[0].error is Rejected("a"))
}

///|
async test "a wrapped core topic raises the core PublishFailed unchanged" {
  let log = []
  let wrapped = @mediator_async.Topic::from_sync(core_orders(log))
  try wrapped.publish((), Order("a")) catch {
    error => expect_core_failure(error)
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["core one", "core two", "core three"])
  log.clear()
  try wrapped.publish_concurrent((), Order("a")) catch {
    error => expect_core_failure(error)
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["core one", "core two", "core three"])
}

///|
async test "a wrapped core topic with no failure finishes with no error" {
  let log = []
  let core : @mediator.Topic[Unit, Order] = @mediator.topic((_, _) => {
    log.push("core one")
  })
  @mediator_async.Topic::from_sync(core).publish((), Order("a"))
  assert_eq(log, ["core one"])
}

///|
async test "after add, the wrapped core publish is the handler at position 1" {
  let log = []
  let all = @mediator_async.Topic::from_sync(core_orders(log)).add((_, _) => {
    @aio.sleep(1)
    log.push("async two")
    raise Rejected("late")
  })
  try all.publish((), Order("a")) catch {
    @mediator.PublishFailed(handlers~, failures~) => {
      assert_eq(handlers, 2)
      assert_eq(failures.to_array().map(failure => failure.position), [1, 2])
      expect_core_failure(failures.to_array()[0].error)
      assert_true(failures.to_array()[1].error is Rejected("late"))
    }
    other => fail("publish raised another error: \{other}")
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["core one", "core two", "core three", "async two"])
}

///|
async test "middleware preserves wrapped core failures on both publish paths" {
  let log = []
  let wraps = Ref(0)
  let wrapped = @mediator_async.Topic::from_sync(core_orders(log)).use_(
    @mediator_async.middleware((next, ctx, ev) => {
      wraps.val += 1
      next(ctx, ev)
    }),
  )
  try wrapped.publish((), Order("a")) catch {
    error => expect_core_failure(error)
  } noraise { _ => fail("expected failure") }
  try wrapped.publish_concurrent((), Order("a")) catch {
    error => expect_core_failure(error)
  } noraise { _ => fail("expected failure") }
  assert_eq(wraps.val, 2)
  assert_eq(log, ["core one", "core two", "core three", "core one", "core two", "core three"])
}

///|
async test "concurrent add preserves the original core wrapper and nested failures" {
  let log = []
  let wrapped = @mediator_async.Topic::from_sync(core_orders(log))
  let all = wrapped.add((_, _) => {
    @aio.sleep(1)
    log.push("async two")
    raise Rejected("late")
  })
  try all.publish_concurrent((), Order("a")) catch {
    @mediator.PublishFailed(handlers~, failures~) => {
      assert_eq(handlers, 2)
      assert_eq(failures.to_array().map(failure => failure.position), [1, 2])
      guard failures.get(0) is Some(first) else { fail("missing core failure") }
      guard failures.get(1) is Some(second) else { fail("missing async failure") }
      expect_core_failure(first.error)
      assert_true(second.error is Rejected("late"))
    }
    other => fail("unexpected error: \{other}")
  } noraise { _ => fail("expected failure") }
  assert_true(log.contains("async two"))
  log.clear()
  try wrapped.publish_concurrent((), Order("a")) catch {
    error => expect_core_failure(error)
  } noraise { _ => fail("expected failure") }
  assert_eq(log, ["core one", "core two", "core three"])
}
