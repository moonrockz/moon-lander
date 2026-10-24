///|
struct Greet(String)

///|
suberror GreetError {
  Refused(String)
} derive(Debug)

///|
/// A sender whose handler records `handler` and gives `Hi <name>`.
fn greeter(log : Array[String]) -> @mediator.Sender[Unit, Greet, String] {
  @mediator.sender((_, req) => {
    log.push("handler")
    let Greet(name) = req
    "Hi " + name
  })
}

///|
/// A middleware that records its name before and after the next step.
fn traced(
  log : Array[String],
  name : String,
) -> @mediator.Middleware[Unit, Greet, String] {
  @mediator.middleware((next, ctx, req) => {
    log.push(name + " in")
    let reply = next(ctx, req)
    log.push(name + " out")
    reply
  })
}

///|
test "use_ gives a new sender and the original sender stays without middleware" {
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
test "before and after helpers record around the handler" {
  let log = []
  let logged = greeter(log)
    .use_(
      @mediator.before((_, req) => {
        let Greet(name) = req
        log.push("before " + name)
      }),
    )
    .use_(@mediator.after((_, _, reply) => log.push("after " + reply)))
  assert_eq(logged.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["before Ann", "handler", "after Hi Ann"])
}

///|
test "after does not run when the next step raises" {
  let log = []
  let failing : @mediator.Sender[Unit, Greet, String] = @mediator.sender((_, _) => {
    raise Refused("closed")
  })
  let logged = failing.use_(
    @mediator.after((_, _, reply) => log.push("after " + reply)),
  )
  try logged.send((), Greet("Ann")) catch {
    Refused(text) => assert_eq(text, "closed")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  assert_eq(log, [])
}

///|
test "finally runs after a reply and after an error" {
  let log = []
  let hook = @mediator.finally_((_, req) => {
    let Greet(name) = req
    log.push("finally " + name)
  })
  let ok = greeter(log).use_(hook)
  assert_eq(ok.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["handler", "finally Ann"])
  log.clear()
  let failing : @mediator.Sender[Unit, Greet, String] = @mediator.sender((_, _) => {
    raise Refused("closed")
  })
  try failing.use_(hook).send((), Greet("Bo")) catch {
    Refused(text) => assert_eq(text, "closed")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  assert_eq(log, ["finally Bo"])
}

///|
test "a middleware that gives a reply ends the call without the handler" {
  let log = []
  let cached = greeter(log).use_(
    @mediator.middleware((_, _, _) => "Hi from cache"),
  )
  assert_eq(cached.send((), Greet("Ann")), "Hi from cache")
  assert_eq(log, [])
}

///|
test "a middleware changes the request before the next step" {
  let log = []
  let upper = greeter(log).use_(
    @mediator.middleware((next, ctx, req) => {
      let Greet(name) = req
      next(ctx, Greet(name.to_upper()))
    }),
  )
  assert_eq(upper.send((), Greet("Ann")), "Hi ANN")
  assert_eq(log, ["handler"])
}

///|
test "a middleware changes the reply after the next step" {
  let log = []
  let loud = greeter(log).use_(
    @mediator.middleware((next, ctx, req) => next(ctx, req) + "!"),
  )
  assert_eq(loud.send((), Greet("Ann")), "Hi Ann!")
}

///|
test "the first middleware attached is the outermost step" {
  let log = []
  let ordered = greeter(log).use_(traced(log, "A")).use_(traced(log, "B"))
  assert_eq(ordered.send((), Greet("Ann")), "Hi Ann")
  assert_eq(log, ["A in", "B in", "handler", "B out", "A out"])
}

///|
test "a middleware that catches the error of the next step gives a reply" {
  let failing : @mediator.Sender[Unit, Greet, String] = @mediator.sender((_, _) => {
    raise Refused("closed")
  })
  let recovered = failing.use_(
    @mediator.middleware((next, ctx, req) => {
      next(ctx, req) catch {
        Refused(text) => "Sorry: " + text
        other => raise other
      }
    }),
  )
  assert_eq(recovered.send((), Greet("Ann")), "Sorry: closed")
}

///|
test "a middleware that does not catch passes the same error out of send" {
  let log = []
  let failing : @mediator.Sender[Unit, Greet, String] = @mediator.sender((_, _) => {
    raise Refused("closed")
  })
  try failing.use_(traced(log, "A")).send((), Greet("Ann")) catch {
    Refused(text) => assert_eq(text, "closed")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  assert_eq(log, ["A in"])
}
