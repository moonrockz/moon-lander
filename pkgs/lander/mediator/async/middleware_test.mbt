///|
struct Greet(String)

///|
suberror GreetError {
  Refused(String)
} derive(Debug)

///|
/// A sender whose handler waits, records `handler` and gives `Hi <name>`.
fn greeter(log : Array[String]) -> @mediator_async.Sender[Unit, Greet, String] {
  @mediator_async.sender((_, req) => {
    @async.sleep(1)
    log.push("handler")
    let Greet(name) = req
    "Hi " + name
  })
}

///|
/// A sender whose handler waits, records `handler` and raises `Refused`.
fn refuser(log : Array[String]) -> @mediator_async.Sender[Unit, Greet, String] {
  @mediator_async.sender((_, _) => {
    @async.sleep(1)
    log.push("handler")
    raise Refused("closed")
  })
}

///|
/// A middleware that waits and records its name before and after the next
/// step.
fn traced(
  log : Array[String],
  name : String,
) -> @mediator_async.Middleware[Unit, Greet, String] {
  @mediator_async.middleware((next, ctx, req) => {
    @async.sleep(1)
    log.push(name + " in")
    let reply = next(ctx, req)
    log.push(name + " out")
    reply
  })
}

///|
/// Check that `send` raises `Refused("closed")` and gives no reply.
async fn expect_refused(
  sender : @mediator_async.Sender[Unit, Greet, String],
) -> Unit {
  try sender.send((), Greet("Ann")) catch {
    Refused(text) => assert_eq(text, "closed")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}

///|
async test "use_ gives a new sender and the original sender stays without middleware" {
  let log = []
  let plain = greeter(log)
  let wrapped = plain.use_(traced(log, "A"))
  assert_eq(plain.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["handler"])
  log.clear()
  assert_eq(wrapped.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["A in", "handler", "A out"])
}

///|
async test "before and after hooks wait and record around the handler" {
  let log = []
  let logged = greeter(log)
    .use_(
      @mediator_async.before((_, req) => {
        @async.sleep(1)
        let Greet(name) = req
        log.push("before " + name)
      }),
    )
    .use_(
      @mediator_async.after((_, _, reply) => {
        @async.sleep(1)
        log.push("after " + reply)
      }),
    )
  assert_eq(logged.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["before Ann", "handler", "after Hi Ann"])
}

///|
async test "after does not run when the next step raises" {
  let log = []
  let logged = refuser(log).use_(
    @mediator_async.after((_, _, reply) => log.push("after " + reply)),
  )
  expect_refused(logged)
  assert_eq(log, ["handler"])
}

///|
async test "finally runs after a reply and after an error" {
  let log = []
  let hook = @mediator_async.finally_((_, req) => {
    let Greet(name) = req
    log.push("finally " + name)
  })
  assert_eq(greeter(log).use_(hook).send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["handler", "finally Ann"])
  log.clear()
  expect_refused(refuser(log).use_(hook))
  assert_eq(log, ["handler", "finally Ann"])
}

///|
async test "the first middleware attached is the outermost step" {
  let log = []
  let ordered = greeter(log).use_(traced(log, "A")).use_(traced(log, "B"))
  assert_eq(ordered.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["A in", "B in", "handler", "B out", "A out"])
}

///|
async test "a middleware that replies without the next step skips the handler" {
  let log = []
  let cached = greeter(log).use_(
    @mediator_async.middleware((_, _, _) => {
      @async.sleep(1)
      "cached"
    }),
  )
  assert_eq(cached.send((), Greet("Ann")), "cached")
  assert_eq(log, [])
}

///|
async test "a middleware can change the request and the reply" {
  let log = []
  let changed = greeter(log).use_(
    @mediator_async.middleware((next, ctx, req) => {
      let Greet(name) = req
      next(ctx, Greet(name.to_upper())) + "!"
    }),
  )
  assert_eq(changed.send((), Greet("Ann")), "Hi ANN!")
}

///|
async test "a middleware that catches the error of the next step can reply" {
  let log = []
  let recovered = refuser(log).use_(
    @mediator_async.middleware((next, ctx, req) => {
      next(ctx, req) catch {
        Refused(text) => "fallback " + text
        other => raise other
      }
    }),
  )
  assert_eq(recovered.send((), Greet("Ann")), "fallback closed")
  assert_eq(log, ["handler"])
}

///|
async test "a middleware that does not catch passes the same error out" {
  let log = []
  expect_refused(refuser(log).use_(traced(log, "A")))
  assert_eq(log, ["A in", "handler"])
}
