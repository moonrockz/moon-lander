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
test "a handler and a middleware read the services from the context" {
  let seen = []
  let hello : @mediator.Sender[Scope, Hello, String] = @mediator.sender((
    ctx,
    req,
  ) => {
    let Hello(name) = req
    ctx.deps.greeting + " " + name
  })
  let watched = hello.use_(
    @mediator.before((ctx, _) => seen.push(ctx.deps.greeting)),
  )
  let ctx = { deps: { greeting: "Hi", }, }
  assert_eq(watched.send(ctx, Hello("Ann")), "Hi Ann")
  ctx.deps.greeting = "Hello"
  assert_eq(watched.send(ctx, Hello("Ann")), "Hello Ann")
  assert_eq(seen, ["Hi", "Hello"])
}

///|
test "the core gives the exact context value and holds none after a call" {
  let seen : Array[Scope] = []
  let hello : @mediator.Sender[Scope, Hello, String] = @mediator.sender((ctx, _) => {
    seen.push(ctx)
    ctx.deps.greeting
  })
  let first = { deps: { greeting: "one", }, }
  let second = { deps: { greeting: "two", }, }
  assert_eq(hello.send(first, Hello("Ann")), "one")
  assert_eq(hello.send(second, Hello("Ann")), "two")
  assert_eq(seen.length(), 2)
  assert_true(physical_equal(seen[0], first))
  assert_true(physical_equal(seen[1], second))
}

///|
test "a topic gives each handler the context value" {
  let seen = []
  let joined : @mediator.Topic[Scope, Hello] = @mediator.topic((ctx, _) => {
    seen.push(ctx.deps.greeting)
  })
  joined
  .add((ctx, _) => seen.push(ctx.deps.greeting + "!"))
  .publish({ deps: { greeting: "Hi", }, }, Hello("Ann"))
  assert_eq(seen, ["Hi", "Hi!"])
}
