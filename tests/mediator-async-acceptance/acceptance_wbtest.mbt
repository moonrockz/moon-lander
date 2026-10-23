///|
/// One `async test` for each scenario of the `mediator-async` specification.
/// moonspec steps are synchronous and cannot await a send, so the scenarios
/// are plain async tests. Timing scenarios use wide margins and order logs,
/// not clock values.

///|
struct Services {
  mut greeting : String
}

///|
struct AcceptanceContext {
  services : Services
}

///|
struct Ping(String)

///|
struct Joined(String)

///|
suberror AcceptanceError {
  Closed(String)
}

///|
fn empty_context() -> AcceptanceContext {
  { services: { greeting: "Pong" } }
}

///|
/// A topic handler that records its start, waits `wait_ms`, records its end,
/// and raises `Closed(name)` when `fails` is true.
fn handler(
  log : Array[String],
  name : String,
  wait_ms~ : Int = 10,
  fails~ : Bool = false,
) -> async (AcceptanceContext, Joined) -> Unit {
  (_, ev) => {
    let Joined(person) = ev
    log.push(name + " start " + person)
    @async.sleep(wait_ms)
    log.push(name + " end " + person)
    if fails {
      raise Closed(name)
    }
  }
}

///|
/// The positions and `Closed` names of a `PublishFailed`, and its handler
/// count.
fn publish_failures(error : Error) -> (Int, Array[(Int, String)]) raise {
  guard error is @mediator.PublishFailed(handlers~, failures~) else {
    fail("publish raised another error: \{error}")
  }
  let seen = failures.map(failure => {
    guard failure.error is Closed(name) else {
      fail("a failure holds another error: \{failure.error}")
    }
    (failure.position, name)
  })
  (handlers, seen)
}

///|
/// A ping sender whose handler waits `wait_ms`, records its end and gives
/// `<greeting>: <text>` from the context.
fn ping_sender(
  log : Array[String],
  wait_ms~ : Int = 10,
) -> @mediator_async.Sender[AcceptanceContext, Ping, String] {
  @mediator_async.sender((ctx, req) => {
    log.push("ping start")
    @async.sleep(wait_ms)
    log.push("ping end")
    let Ping(text) = req
    ctx.services.greeting + ": " + text
  })
}

// Requirement: Typed async sender registration

///|
async test "Send a ping through an async sender" {
  let log = []
  let ping = ping_sender(log)
  assert_eq(ping.send(empty_context(), Ping("Hello")), "Pong: Hello")
  assert_eq(log, ["ping start", "ping end"])
}

///|
/// Scenario "A request of the wrong type" is a compile error. With
/// `ping : Sender[AcceptanceContext, Ping, String]` and a record `stop : Stop`,
/// `ping.send(ctx, stop)` gives `Error: [4014] Expr Type Mismatch, has type :
/// Stop, wanted : Ping` (moonc v0.10.17). This test proves that the sender
/// type fixes the request type that compiles.
async test "A request of the wrong type" {
  let ping : @mediator_async.Sender[AcceptanceContext, Ping, String] = ping_sender(
    [],
  )
  assert_eq(ping.send(empty_context(), Ping("typed")), "Pong: typed")
}

// Requirement: Async send passes a handler error out unchanged

///|
async test "Async handler raises" {
  let failing : @mediator_async.Sender[AcceptanceContext, Ping, String] = @mediator_async.sender((
    _,
    _,
  ) => {
    @async.sleep(10)
    raise Closed("closed")
  })
  try failing.send(empty_context(), Ping("Hello")) catch {
    Closed(text) => assert_eq(text, "closed")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}

// Requirement: Sequential publish runs every handler and reports every failure

///|
async test "Second of three async handlers raises" {
  let log = []
  let topic = @mediator_async.topic(handler(log, "one"))
    .add(handler(log, "two", fails=true))
    .add(handler(log, "three"))
  try topic.publish(empty_context(), Joined("Ann")) catch {
    error => assert_eq(publish_failures(error), (3, [(2, "two")]))
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, [
    "one start Ann", "one end Ann", "two start Ann", "two end Ann", "three start Ann",
    "three end Ann",
  ])
}

///|
async test "No async handler raises" {
  let log = []
  let topic = @mediator_async.topic(handler(log, "one")).add(handler(log, "two"))
  topic.publish(empty_context(), Joined("Ann"))
  assert_eq(log, ["one start Ann", "one end Ann", "two start Ann", "two end Ann"])
}

// Requirement: Concurrent publish runs every handler at the same time

///|
async test "Handlers overlap" {
  let log = []
  let topic = @mediator_async.topic(handler(log, "one", wait_ms=200)).add(
    handler(log, "two", wait_ms=10),
  )
  topic.publish_concurrent(empty_context(), Joined("Ann"))
  assert_eq(log, ["one start Ann", "two start Ann", "two end Ann", "one end Ann"])
}

///|
async test "Failures in add order" {
  let log = []
  let topic = @mediator_async.topic(
    handler(log, "one", wait_ms=200, fails=true),
  )
    .add(handler(log, "two", wait_ms=100))
    .add(handler(log, "three", wait_ms=10, fails=true))
  try topic.publish_concurrent(empty_context(), Joined("Ann")) catch {
    error => assert_eq(publish_failures(error), (3, [(1, "one"), (3, "three")]))
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log.filter(line => line.contains("end")), [
    "three end Ann", "two end Ann", "one end Ann",
  ])
}

// Requirement: No publish returns before its handlers end

///|
async test "Return after the last handler" {
  let log = []
  let topic = @mediator_async.topic(handler(log, "one", wait_ms=100)).add(
    handler(log, "two", wait_ms=10),
  )
  topic.publish(empty_context(), Joined("Ann"))
  assert_eq(log.length(), 4)
  log.clear()
  topic.publish_concurrent(empty_context(), Joined("Ann"))
  assert_eq(log.length(), 4)
}

// Requirement: Caller cancellation stops the call and passes out unchanged

///|
async test "Cancel a send" {
  let log = []
  let ping = ping_sender(log, wait_ms=1000)
  let reply = @async.with_timeout_opt(50, () => {
    ping.send(empty_context(), Ping("Hello"))
  })
  assert_eq(reply, None)
  @async.sleep(20)
  assert_eq(log, ["ping start"])
}

///|
async test "Cancel a sequential publish" {
  let log = []
  let topic = @mediator_async.topic(handler(log, "one"))
    .add(handler(log, "two", wait_ms=1000))
    .add(handler(log, "three"))
  let outcome = @async.with_timeout_opt(100, () => {
    topic.publish(empty_context(), Joined("Ann"))
  })
  assert_eq(outcome, None)
  @async.sleep(20)
  assert_eq(log, ["one start Ann", "one end Ann", "two start Ann"])
}

///|
async test "Cancel a concurrent publish" {
  let log = []
  let topic = @mediator_async.topic(handler(log, "one", wait_ms=1000)).add(
    handler(log, "two", wait_ms=1000),
  )
  let outcome = @async.with_timeout_opt(50, () => {
    topic.publish_concurrent(empty_context(), Joined("Ann"))
  })
  assert_eq(outcome, None)
  @async.sleep(20)
  assert_eq(log, ["one start Ann", "two start Ann"])
}

// Requirement: A timeout inside a handler is an ordinary failure

///|
async test "One handler times out" {
  let log = []
  let topic = @mediator_async.topic((_, _) => {
    @async.with_timeout(10, () => @async.sleep(1000), error=Closed("own limit"))
  }).add(handler(log, "two"))
  try topic.publish(empty_context(), Joined("Ann")) catch {
    error => assert_eq(publish_failures(error), (2, [(1, "own limit")]))
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["two start Ann", "two end Ann"])
}

// Requirement: The timeout middleware ends a slow call

///|
async test "The handler is too slow" {
  let log = []
  let limited = ping_sender(log, wait_ms=1000).use_(@mediator_async.timeout(50))
  try limited.send(empty_context(), Ping("Hello")) catch {
    @mediator.TimedOut(after_ms~) => assert_eq(after_ms, 50)
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  @async.sleep(20)
  assert_eq(log, ["ping start"])
}

///|
async test "The handler ends in time" {
  let log = []
  let limited = ping_sender(log, wait_ms=10).use_(@mediator_async.timeout(1000))
  assert_eq(limited.send(empty_context(), Ping("Hello")), "Pong: Hello")
}

// Requirement: Async middleware wraps send and publish

///|
async test "Two middleware on one async sender" {
  let log = []
  fn traced(
    name : String,
  ) -> @mediator_async.Middleware[AcceptanceContext, Ping, String] {
    @mediator_async.middleware((next, ctx, req) => {
      log.push(name + " in")
      let reply = next(ctx, req)
      log.push(name + " out")
      reply
    })
  }

  let ordered = ping_sender(log).use_(traced("A")).use_(traced("B"))
  assert_eq(ordered.send(empty_context(), Ping("Hello")), "Pong: Hello")
  assert_eq(log, ["A in", "B in", "ping start", "ping end", "B out", "A out"])
}

///|
async test "Middleware ends the call" {
  let log = []
  let cached = ping_sender(log).use_(
    @mediator_async.middleware((_, _, _) => "cached"),
  )
  assert_eq(cached.send(empty_context(), Ping("Hello")), "cached")
  assert_eq(log, [])
}

// Requirement: The finally hook runs on every outcome

///|
async test "Finally after a cancellation" {
  let log = []
  let hooked = ping_sender(log, wait_ms=1000).use_(
    @mediator_async.finally_((_, _) => log.push("finally")),
  )
  let reply = @async.with_timeout_opt(50, () => {
    hooked.send(empty_context(), Ping("Hello"))
  })
  assert_eq(reply, None)
  @async.sleep(20)
  assert_eq(log, ["ping start", "finally"])
}

// Requirement: The context value passes unchanged

///|
async test "Handler reads services from the context" {
  let ctx = empty_context()
  ctx.services.greeting = "Hello"
  assert_eq(ping_sender([]).send(ctx, Ping("Ann")), "Hello: Ann")
}

// Requirement: Core senders and topics work as async ones

///|
async test "Wrap a core sender" {
  let log = []
  let core : @mediator.Sender[AcceptanceContext, Ping, String] = @mediator.sender((
    ctx,
    req,
  ) => {
    log.push("core handler")
    let Ping(text) = req
    ctx.services.greeting + ": " + text
  })
  let logged = core.use_(
    @mediator.middleware((next, ctx, req) => {
      log.push("core log in")
      let reply = next(ctx, req)
      log.push("core log out")
      reply
    }),
  )
  let wrapped = @mediator_async.Sender::from_sync(logged)
  assert_eq(wrapped.send(empty_context(), Ping("Hello")), "Pong: Hello")
  assert_eq(log, ["core log in", "core handler", "core log out"])
}

// Requirement: Same async behavior on wasm, js and native. Scenario "The
// acceptance suite on each target" is `mise run check:mediator`, which runs
// this suite on wasm, js and native and fails a target that runs zero tests.
