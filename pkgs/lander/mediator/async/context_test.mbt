///|
struct Deps {
  mut greeting : String
}

///|
struct Scope {
  deps : Deps
}

///|
struct Hello(String)

///|
async test "a handler and a middleware read the context value after a wait" {
  let seen = []
  let hello : @mediator_async.Sender[Scope, Hello, String] = @mediator_async.sender((
    ctx,
    req,
  ) => {
    @aio.sleep(5)
    let Hello(name) = req
    ctx.deps.greeting + " " + name
  })
  let watched = hello.use_(
    @mediator_async.before((ctx, _) => {
      @aio.sleep(5)
      seen.push(ctx.deps.greeting)
    }),
  )
  let scope = { deps: { greeting: "Hi" } }
  assert_eq(watched.send(scope, Hello("Ann")), "Hi Ann")
  scope.deps.greeting = "Hello"
  assert_eq(watched.send(scope, Hello("Ann")), "Hello Ann")
  assert_eq(seen, ["Hi", "Hello"])
}

///|
async test "each publish handler gets the context value of its caller" {
  let seen = []
  let entered : @mediator_async.Topic[Scope, Hello] = @mediator_async.topic((
    ctx,
    _,
  ) => {
    @aio.sleep(100)
    seen.push("one " + ctx.deps.greeting)
  })
  let all = entered.add((ctx, _) => {
    @aio.sleep(5)
    seen.push("two " + ctx.deps.greeting)
  })
  all.publish_concurrent({ deps: { greeting: "Hi" } }, Hello("Ann"))
  assert_eq(seen, ["two Hi", "one Hi"])
}
