///|
struct Entered(String)

///|
suberror JoinError {
  Full(String)
} derive(Debug)

///|
/// An async handler that checks the event, records its start, waits
/// `wait_ms`, records its end, and raises `Full(name)` when `fails` is true.
fn step(
  log : Array[String],
  name : String,
  wait_ms~ : Int = 10,
  fails~ : Bool = false,
) -> async (Unit, Entered) -> Unit {
  (_, ev) => {
    let Entered(person) = ev
    assert_eq(person, "Ann")
    log.push(name + " start")
    @aio.sleep(wait_ms)
    log.push(name + " end")
    if fails {
      raise Full(name)
    }
  }
}

///|
/// Check that `error` is one `PublishFailed` for `handlers` handlers whose
/// failures are `Full` errors with the given positions and names.
fn expect_publish_failed(
  error : Error,
  handlers~ : Int,
  failures~ : Array[(Int, String)],
) -> Unit raise {
  guard error is @mediator.PublishFailed(handlers=count, failures=got) else {
    fail("publish raised another error: \{error}")
  }
  assert_eq(count, handlers)
  let seen = got.to_array().map(failure => {
    guard failure.error is Full(name) else {
      fail("a failure holds another error: \{failure.error}")
    }
    (failure.position, name)
  })
  assert_eq(seen, failures)
}

///|
async test "publish runs the handlers one at a time in add order" {
  let log = []
  let all = @mediator_async.topic(step(log, "one"))
    .add(step(log, "two"))
    .add(step(log, "three"))
  all.publish((), Entered("Ann"))
  assert_eq(log, [
    "one start", "one end", "two start", "two end", "three start", "three end",
  ])
}

///|
async test "publish runs every handler after the second of three raises" {
  let log = []
  let all = @mediator_async.topic(step(log, "one"))
    .add(step(log, "two", fails=true))
    .add(step(log, "three"))
  try all.publish((), Entered("Ann")) catch {
    error => expect_publish_failed(error, handlers=3, failures=[(2, "two")])
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, [
    "one start", "one end", "two start", "two end", "three start", "three end",
  ])
}

///|
async test "publish with no failing handler finishes with no error" {
  let log = []
  let all = @mediator_async.topic(step(log, "one")).add(step(log, "two"))
  try all.publish((), Entered("Ann")) catch {
    error => fail("publish raised an error: \{error}")
  }
  assert_eq(log, ["one start", "one end", "two start", "two end"])
}

///|
async test "publish_concurrent overlaps the handlers and returns after both end" {
  let log = []
  let all = @mediator_async.topic(step(log, "one", wait_ms=100)).add(
    step(log, "two", wait_ms=10),
  )
  all.publish_concurrent((), Entered("Ann"))
  assert_eq(log, ["one start", "two start", "two end", "one end"])
}

///|
async test "publish_concurrent lists failures in add order, not end order" {
  let log = []
  let all = @mediator_async.topic(step(log, "one", wait_ms=100, fails=true))
    .add(step(log, "two", wait_ms=50))
    .add(step(log, "three", wait_ms=10, fails=true))
  try all.publish_concurrent((), Entered("Ann")) catch {
    error =>
      expect_publish_failed(error, handlers=3, failures=[
        (1, "one"),
        (3, "three"),
      ])
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, [
    "one start", "two start", "three start", "three end", "two end", "one end",
  ])
}

///|
async test "publish_concurrent with no failing handler finishes with no error" {
  let log = []
  let all = @mediator_async.topic(step(log, "one")).add(step(log, "two"))
  try all.publish_concurrent((), Entered("Ann")) catch {
    error => fail("publish raised an error: \{error}")
  }
  assert_eq(log.length(), 4)
}

///|
async test "a topic middleware gets the combined error of both publish operations" {
  let log = []
  let caught = []
  let guarded = @mediator_async.topic(step(log, "one"))
    .add(step(log, "two", fails=true))
    .use_(
      @mediator_async.middleware((next, ctx, ev) => {
        next(ctx, ev) catch {
          error => caught.push(error)
        }
      }),
    )
  guarded.publish((), Entered("Ann"))
  guarded.publish_concurrent((), Entered("Ann"))
  assert_eq(caught.length(), 2)
  expect_publish_failed(caught[0], handlers=2, failures=[(2, "two")])
  expect_publish_failed(caught[1], handlers=2, failures=[(2, "two")])
  assert_eq(log.length(), 8)
}

///|
async test "topic middleware runs in attach order around the handlers" {
  let log = []
  fn traced(name : String) -> @mediator_async.Middleware[Unit, Entered, Unit] {
    @mediator_async.middleware((next, ctx, ev) => {
      log.push(name + " in")
      next(ctx, ev)
      log.push(name + " out")
    })
  }

  let first = @mediator_async.topic(step(log, "one"))
  let ordered = first.use_(traced("A")).use_(traced("B"))
  ordered.publish((), Entered("Ann"))
  assert_eq(log, ["A in", "B in", "one start", "one end", "B out", "A out"])
  log.clear()
  first.publish((), Entered("Ann"))
  assert_eq(log, ["one start", "one end"])
}
