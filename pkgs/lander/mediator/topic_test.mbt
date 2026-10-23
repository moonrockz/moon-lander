///|
struct Entered(String)

///|
suberror JoinError {
  Full(String)
} derive(Debug)

///|
test "publish runs each handler one time in add order" {
  let log = []
  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, ev) => {
    let Entered(name) = ev
    log.push("one " + name)
  })
  let all = entered
    .add((_, ev) => {
      let Entered(name) = ev
      log.push("two " + name)
    })
    .add((_, ev) => {
      let Entered(name) = ev
      log.push("three " + name)
    })
  let reply : Unit = all.publish((), Entered("Ann"))
  assert_eq(reply, ())
  assert_eq(log, ["one Ann", "two Ann", "three Ann"])
}

///|
/// Check that `error` is one `PublishFailed` for `handlers` handlers whose
/// failures are `Full` errors with the given positions and names.
fn expect_publish_failed(
  error : Error,
  handlers~ : Int32,
  failures~ : Array[(Int32, String)],
) -> Unit raise {
  guard error is @mediator.PublishFailed(handlers=count, failures=got) else {
    fail("publish raised another error: \{error}")
  }
  assert_eq(count, handlers)
  let seen = got.map(failure => {
    guard failure.error is Full(name) else {
      fail("a failure holds another error: \{failure.error}")
    }
    (failure.position, name)
  })
  assert_eq(seen, failures)
}

///|
test "publish runs every handler after the second of three raises" {
  let log = []
  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, _) => {
    log.push("one")
  })
  let all = entered
    .add((_, ev) => {
      log.push("two")
      let Entered(name) = ev
      raise Full(name)
    })
    .add((_, _) => log.push("three"))
  try all.publish((), Entered("Ann")) catch {
    error => expect_publish_failed(error, handlers=3, failures=[(2, "Ann")])
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["one", "two", "three"])
}

///|
test "publish lists two failures in add order with their own errors" {
  let log = []
  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, _) => {
    log.push("one")
  })
  let all = entered
    .add((_, _) => {
      log.push("two")
      raise Full("second")
    })
    .add((_, _) => {
      log.push("three")
      raise Full("third")
    })
  try all.publish((), Entered("Ann")) catch {
    error =>
      expect_publish_failed(error, handlers=3, failures=[
        (2, "second"),
        (3, "third"),
      ])
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["one", "two", "three"])
}

///|
test "publish with no failing handler finishes with no error" {
  let log = []
  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, _) => {
    log.push("one")
  })
  let all = entered.add((_, _) => log.push("two"))
  all.publish((), Entered("Ann")) catch {
    error => fail("publish raised an error: \{error}")
  }
  assert_eq(log, ["one", "two"])
}

///|
test "a topic middleware gets the combined error and can catch it" {
  let log = []
  let caught = []
  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, _) => {
    log.push("one")
  })
  let guarded = entered
    .add((_, _) => {
      log.push("two")
      raise Full("second")
    })
    .use_(
      @mediator.middleware((next, ctx, ev) => {
        next(ctx, ev) catch {
          error => caught.push(error)
        }
      }),
    )
  guarded.publish((), Entered("Ann")) catch {
    error => fail("publish raised an error: \{error}")
  }
  assert_eq(log, ["one", "two"])
  assert_eq(caught.length(), 1)
  expect_publish_failed(caught[0], handlers=2, failures=[(2, "second")])
}

///|
test "topic middleware runs in attach order around the handlers" {
  let log = []
  fn traced(name : String) -> @mediator.Middleware[Unit, Entered, Unit] {
    @mediator.middleware((next, ctx, ev) => {
      log.push(name + " in")
      next(ctx, ev)
      log.push(name + " out")
    })
  }

  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, _) => {
    log.push("one")
  })
  let ordered = entered
    .add((_, _) => log.push("two"))
    .use_(traced("A"))
    .use_(traced("B"))
  ordered.publish((), Entered("Ann"))
  assert_eq(log, ["A in", "B in", "one", "two", "B out", "A out"])
  log.clear()
  entered.publish((), Entered("Ann"))
  assert_eq(log, ["one"])
}

///|
test "a topic middleware can end a publish without the handlers" {
  let log = []
  let entered : @mediator.Topic[Unit, Entered] = @mediator.topic((_, _) => {
    log.push("one")
  })
  entered
  .use_(@mediator.middleware((_, _, _) => ()))
  .publish((), Entered("Ann"))
  assert_eq(log, [])
}
