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
struct Stop(Int32)

///|
struct Joined(String)

///|
suberror AcceptanceError {
  Closed(String)
}

///|
struct MediatorWorld {
  ctx : AcceptanceContext
  log : Array[String]
  mut ping : @mediator.Sender[AcceptanceContext, Ping, String]?
  mut stop : @mediator.Sender[AcceptanceContext, Stop, Int32]?
  mut topic : @mediator.Topic[AcceptanceContext, Joined]?
  mut reply : String?
  mut error : String?
  mut publish_handlers : Int32?
  publish_failures : Array[String]
}

///|
fn MediatorWorld::MediatorWorld() -> MediatorWorld {
  {
    ctx: { services: { greeting: "Pong", }, },
    log: [],
    ping: None,
    stop: None,
    topic: None,
    reply: None,
    error: None,
    publish_handlers: None,
    publish_failures: [],
  }
}

///|
fn MediatorWorld::ping_sender(
  self : MediatorWorld,
) -> @mediator.Sender[AcceptanceContext, Ping, String] raise {
  guard self.ping is Some(ping) else { fail("build the ping sender first") }
  ping
}

///|
fn MediatorWorld::handler(
  self : MediatorWorld,
  name : String,
  fails~ : Bool,
) -> (AcceptanceContext, Joined) -> Unit raise {
  (_, ev) => {
    let Joined(person) = ev
    self.log.push(name + " " + person)
    if fails {
      raise Closed(name)
    }
  }
}

///|
fn MediatorWorld::traced(
  self : MediatorWorld,
  name : String,
) -> @mediator.Middleware[AcceptanceContext, Ping, String] {
  @mediator.middleware((next, ctx, req) => {
    self.log.push(name + " in")
    let reply = next(ctx, req)
    self.log.push(name + " out")
    reply
  })
}

///|
impl @moonspec.World for MediatorWorld with fn configure(self, setup) {
  setup.given0("a ping sender", () => {
    self.ping = Some(
      @mediator.sender((ctx, req) => {
        self.log.push("ping handler")
        let Ping(text) = req
        ctx.services.greeting + ": " + text
      }),
    )
  })
  setup.given1("a ping sender whose handler raises {string}", (text : String) => {
    self.ping = Some(
      @mediator.sender((_, _) => {
        self.log.push("ping handler")
        raise Closed(text)
      }),
    )
  })
  setup.given0("a stop sender", () => {
    self.stop = Some(
      @mediator.sender((_, req) => {
        let Stop(code) = req
        self.log.push("stop handler \{code}")
        code
      }),
    )
  })
  setup.given1("the services greeting {string}", (greeting : String) => {
    self.ctx.services.greeting = greeting
  })
  setup.given1("the log middleware {string} is attached", (name : String) => {
    self.ping = Some(self.ping_sender().use_(self.traced(name)))
  })
  setup.given1("a middleware that replies {string} is attached", (text : String) => {
    self.ping = Some(
      self.ping_sender().use_(@mediator.middleware((_, _, _) => text)),
    )
  })
  setup.given1("a middleware that appends {string} is attached", (text : String) => {
    self.ping = Some(
      self
      .ping_sender()
      .use_(@mediator.middleware((next, ctx, req) => next(ctx, req) + text)),
    )
  })
  setup.given1("a topic that starts with the handler {string}", (name : String) => {
    self.topic = Some(@mediator.topic(self.handler(name, fails=false)))
  })
  setup.given1("the handler {string} is added", (name : String) => {
    guard self.topic is Some(topic) else { fail("build the topic first") }
    self.topic = Some(topic.add(self.handler(name, fails=false)))
  })
  setup.given1("the failing handler {string} is added", (name : String) => {
    guard self.topic is Some(topic) else { fail("build the topic first") }
    self.topic = Some(topic.add(self.handler(name, fails=true)))
  })
  setup.when1("the caller sends the ping {string}", (text : String) => {
    try self.ping_sender().send(self.ctx, Ping(text)) catch {
      Closed(text) => self.error = Some(text)
      other => fail("send raised another error: \{other}")
    } noraise {
      reply => self.reply = Some(reply)
    }
  })
  setup.when1("the caller sends the stop {int}", (code : Int32) => {
    guard self.stop is Some(stop) else { fail("build the stop sender first") }
    @expect.expect(stop.send(self.ctx, Stop(code))).to_equal(code)
  })
  setup.when1("the caller publishes {string}", (name : String) => {
    guard self.topic is Some(topic) else { fail("build the topic first") }
    topic.publish(self.ctx, Joined(name)) catch {
      @mediator.PublishFailed(handlers~, failures~) => {
        self.publish_handlers = Some(handlers)
        for failure in failures.to_array() {
          guard failure.error is Closed(text) else {
            fail("a publish failure holds another error: \{failure.error}")
          }
          self.publish_failures.push("\{failure.position} \{text}")
        }
      }
      other => fail("publish raised another error: \{other}")
    }
  })
  setup.then1("the reply is {string}", (expected : String) => {
    @expect.expect(self.reply).to_equal(Some(expected))
  })
  setup.then0("no reply is given", () => {
    @expect.expect(self.reply).to_equal(None)
  })
  setup.then1("the application error {string} is raised", (expected : String) => {
    @expect.expect(self.error).to_equal(Some(expected))
  })
  setup.then0("no error is raised", () => {
    @expect.expect(self.error).to_equal(None)
    @expect.expect(self.publish_handlers).to_equal(None)
  })
  setup.then1("the publish fails for {int} handlers", (handlers : Int32) => {
    @expect.expect(self.publish_handlers).to_equal(Some(handlers))
  })
  setup.then1("the publish failures are {string}", (expected : String) => {
    @expect.expect(self.publish_failures.join(", ")).to_equal(expected)
  })
  setup.then1("the log is {string}", (expected : String) => {
    @expect.expect(self.log.join(", ")).to_equal(expected)
  })
  setup.then0("the log is empty", () => {
    @expect.expect(self.log.is_empty()).to_be_true()
  })
}

///|
let send_feature : String =
  #|Feature: Send a request through a typed sender
  #|  Scenario: Send a ping
  #|    Given a ping sender
  #|    When the caller sends the ping "Hello"
  #|    Then the reply is "Pong: Hello"
  #|    And the log is "ping handler"
  #|
  #|  Scenario: Two senders stay separate
  #|    Given a ping sender
  #|    And a stop sender
  #|    When the caller sends the ping "Hello"
  #|    Then the log is "ping handler"
  #|    When the caller sends the stop 3
  #|    Then the log is "ping handler, stop handler 3"
  #|
  #|  Scenario: Handler raises
  #|    Given a ping sender whose handler raises "closed"
  #|    When the caller sends the ping "Hello"
  #|    Then the application error "closed" is raised
  #|    And no reply is given

///|
let publish_feature : String =
  #|Feature: Publish an event to a topic
  #|  Scenario: Publish to three handlers
  #|    Given a topic that starts with the handler "one"
  #|    And the handler "two" is added
  #|    And the handler "three" is added
  #|    When the caller publishes "Ann"
  #|    Then the log is "one Ann, two Ann, three Ann"
  #|    And no error is raised
  #|
  #|  Scenario: Second handler raises
  #|    Given a topic that starts with the handler "one"
  #|    And the failing handler "two" is added
  #|    And the handler "three" is added
  #|    When the caller publishes "Ann"
  #|    Then the log is "one Ann, two Ann, three Ann"
  #|    And the publish fails for 3 handlers
  #|    And the publish failures are "2 two"
  #|
  #|  Scenario: Two handlers raise
  #|    Given a topic that starts with the handler "one"
  #|    And the failing handler "two" is added
  #|    And the failing handler "three" is added
  #|    When the caller publishes "Ann"
  #|    Then the log is "one Ann, two Ann, three Ann"
  #|    And the publish fails for 3 handlers
  #|    And the publish failures are "2 two, 3 three"

///|
let middleware_feature : String =
  #|Feature: Middleware wraps a send
  #|  Scenario: Log middleware around a send
  #|    Given a ping sender
  #|    And the log middleware "log" is attached
  #|    When the caller sends the ping "Hello"
  #|    Then the log is "log in, ping handler, log out"
  #|
  #|  Scenario: Middleware ends the call
  #|    Given a ping sender
  #|    And a middleware that replies "cached" is attached
  #|    When the caller sends the ping "Hello"
  #|    Then the reply is "cached"
  #|    And the log is empty
  #|
  #|  Scenario: Middleware changes the reply
  #|    Given a ping sender
  #|    And a middleware that appends "!" is attached
  #|    When the caller sends the ping "Hello"
  #|    Then the reply is "Pong: Hello!"
  #|
  #|  Scenario: Two middleware on one sender
  #|    Given a ping sender
  #|    And the log middleware "A" is attached
  #|    And the log middleware "B" is attached
  #|    When the caller sends the ping "Hello"
  #|    Then the log is "A in, B in, ping handler, B out, A out"

///|
let context_feature : String =
  #|Feature: The context value passes unchanged
  #|  Scenario: Handler reads the services from the context
  #|    Given the services greeting "Hello"
  #|    And a ping sender
  #|    When the caller sends the ping "Ann"
  #|    Then the reply is "Hello: Ann"

///|
/// Run each scenario of `text` with a fresh world and fail on the first scenario
/// that does not pass. `@moonspec.run_or_fail` is async, and wasm-gc has no
/// async test entry, so this suite drives the synchronous runner steps itself to
/// run on all four targets.
fn[W : @moonspec.World] run_scenarios(
  factory : () -> W,
  uri : String,
  text : String,
) -> Unit raise {
  let cache = @runner.FeatureCache::new()
  cache.load_text(uri, text)
  let pickles = @runner.compile_pickles(cache)
  @expect.expect(pickles.is_empty()).to_be_false()
  for pickle in pickles {
    let setup = @moonspec_core.Setup::new()
    @moonspec.World::configure(factory(), setup)
    let result = @runner.execute_scenario(
      setup.step_registry(),
      feature_name=uri,
      scenario_name=pickle.name,
      pickle_id=pickle.id,
      tags=[],
      steps=pickle.steps,
    )
    if result.status != Passed {
      let failures = result.steps
        .filter(step => !step.status.is_passed())
        .map(step => "\{step.keyword}\{step.text}: \{step.status.to_repr()}")
      fail("\{pickle.name} did not pass:\n\{failures.join("\n")}")
    }
  }
}

///|
test "send scenarios" {
  run_scenarios(
    () => MediatorWorld::MediatorWorld(),
    "send.feature",
    send_feature,
  )
}

///|
test "publish scenarios" {
  run_scenarios(
    () => MediatorWorld::MediatorWorld(),
    "publish.feature",
    publish_feature,
  )
}

///|
test "middleware scenarios" {
  run_scenarios(
    () => MediatorWorld::MediatorWorld(),
    "middleware.feature",
    middleware_feature,
  )
}

///|
test "context scenarios" {
  run_scenarios(
    () => MediatorWorld::MediatorWorld(),
    "context.feature",
    context_feature,
  )
}
