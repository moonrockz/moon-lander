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
test "publish stops at the first handler that raises" {
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
    Full(name) => assert_eq(name, "Ann")
    other => fail("publish raised another error: \{other}")
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["one", "two"])
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
