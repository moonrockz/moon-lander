# Async mediator

The `mediator/async` package (`@mediator_async`) is the async form of the
[mediator](../README.mbt.md). A handler is an `async` function, so it can wait
or do I/O through [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async).
The shape is the same as the core: typed values, and the compiler is the
registry. There is no text key and no runtime lookup.

Import the package with an explicit alias, because its last path segment is
`async`, the same as `moonbitlang/async`:

```text
import {
  "moonrockz/moon-lander-core" @lander_core,
  "moonrockz/moon-lander-mediator/async" @mediator_async,
  "moonbitlang/async",
}
```

In your package, `moonbitlang/async` keeps its default alias `@async`. The
examples on this page run as tests of the package itself, where `async` is the
name of the package, so they import `moonbitlang/async` as `@aio`. Write
`@async.sleep` where an example has `@aio.sleep`.

| Target | Supported | Note |
| --- | --- | --- |
| `native`, `js` | All operations | A suspending handler uses the application's async runtime |
| `wasm` | All operations | Runtime operations require `moonbitlang/async` event-loop imports. Non-suspending composition also works under `hosting.run_embedded` |
| `wasm-gc` | Sender and basic middleware | `sender`, `Sender::from_sync`, `use_`, `send`, `middleware`, `before`, `after` and `finally_` need no event loop. Timeout and Topic operations are unavailable |

An import of this public package can now be planned on all four targets. The
sender and basic middleware use one implementation on every target. Timeout and
topic operations stay in files restricted to their existing runtime targets.
No event loop is provided or claimed for wasm-gc.

On wasm and wasm-gc, call a non-suspending send from the async command or hook
that `hosting.run_embedded` executes. It waits for that call to complete before
the embedded step returns. A handler or middleware that actually suspends is
still the embedded driver's typed suspension failure, not successful completion.
Use the async sender itself around a native/JS Promise or other async handler;
dispatching through a sync sender before awaiting that work would finish
middleware scopes too early. The four-target compiled examples and real Promise
acceptance are in `tests/mediator-composition-acceptance`.

Each `mbt check` block on this page runs as a test with `mise run test` on
`wasm`, `js`, and `native`.

## Send a request

`@mediator_async.sender` takes one async handler and gives a
`Sender[C, Req, Res]` value. The handler takes the context value and the
request, can wait, and gives the reply. `Sender::send` waits for the reply.

| Type parameter | Meaning |
| --- | --- |
| `C` | The context value that the caller gives to each send |
| `Req` | The request type. A request of another type does not compile |
| `Res` | The reply type of the handler |

```mbt check
///|
#cfg(not(target="wasm-gc"))
struct Ping(String)

///|
#cfg(not(target="wasm-gc"))
async test "send a ping to a handler that waits" {
  let ping : @mediator_async.Sender[Unit, Ping, String] = @mediator_async.sender((
    _,
    req,
  ) => {
    @aio.sleep(10)
    let Ping(text) = req
    "Pong: " + text
  })
  assert_eq(ping.send((), Ping("Hello")), "Pong: Hello")
}
```

A sender calls its one handler one time for each send. An error that the
handler raises passes out of `send` unchanged. The mediator does not turn an
error into a reply.

## Middleware

An async middleware wraps the next step of a send. It gets `next`, the context
value, and the request. It can wait, run code before and after `next`, change
the request or the reply, give a reply without a call to `next`, or catch the
error of `next`. The helper names and the order rule are the same as in the
core: `Sender::use_` gives a new sender with one more middleware, and the first
middleware that you attach is the outermost step.

| Constructor | Runs |
| --- | --- |
| `@mediator_async.middleware(wrap)` | The async `wrap(next, ctx, req)`, which gives the reply |
| `@mediator_async.before(hook)` | The async `hook(ctx, req)` before the next step |
| `@mediator_async.after(hook)` | The async `hook(ctx, req, reply)` after the next step gives a reply |
| `@mediator_async.finally_(hook)` | The sync `hook(ctx, req)` after the next step: after a reply, after an error, and during a cancellation |

The `finally_` hook is a sync function, so it runs in a `defer` also when the
caller cancels the send. A core `@mediator.Middleware` does not fit an async
sender, because its `next` step is sync.

```mbt check
///|
#cfg(not(target="wasm-gc"))
async test "log middleware around an async send" {
  let log = []
  let ping : @mediator_async.Sender[Unit, Ping, String] = @mediator_async.sender((
    _,
    req,
  ) => {
    @aio.sleep(10)
    log.push("handler")
    let Ping(text) = req
    "Pong: " + text
  })
  let logged = ping
    .use_(
      @mediator_async.middleware((next, ctx, req) => {
        log.push("log in")
        let reply = next(ctx, req)
        log.push("log out")
        reply
      }),
    )
    .use_(@mediator_async.after((_, _, reply) => log.push("reply " + reply)))
    .use_(@mediator_async.finally_((_, _) => log.push("finally")))
  assert_eq(logged.send((), Ping("Hello")), "Pong: Hello")
  assert_eq(log, [
    "log in", "handler", "finally", "reply Pong: Hello", "log out",
  ])
}
```

## Publish an event

`@mediator_async.topic` takes the first async event handler and gives a
`Topic[C, Ev]` value. `Topic::add` gives a new topic with one more handler at
the end, and `Topic::use_` gives a new topic with one more middleware around
the whole publish. A topic has two publish operations. Both follow the
Foundatio.Mediator contract of the core: every handler runs, and a failing
handler does not stop the others.

| Operation | Handlers run | Foundatio model |
| --- | --- | --- |
| `publish` | One at a time, in add order. Each handler starts after the previous one ends | `ForeachAwait` |
| `publish_concurrent` | All at the same time, in one task group. The publish waits for all of them | `TaskWhenAll` |

When one or more handlers raise, both operations raise one
`@mediator.PublishFailed(handlers~, failures~)` after the last handler ends.
The failures are in add order, also when the handlers of a concurrent publish
end in another order. A topic middleware gets that one error from its `next`
and can catch it.

No publish returns before its handlers end. There is no fire-and-forget
publish, because a handler error must not be lost and `moonbitlang/async`
lets no task outlive its task group. An application that wants background
work starts its own task group.

```mbt check
///|
#cfg(not(target="wasm-gc"))
struct Joined(String)

///|
#cfg(not(target="wasm-gc"))
suberror AuditError {
  AuditClosed(String)
}

///|
#cfg(not(target="wasm-gc"))
async test "a concurrent publish runs every handler and lists the failure" {
  let log = []
  let joined : @mediator_async.Topic[Unit, Joined] = @mediator_async.topic((
    _,
    ev,
  ) => {
    @aio.sleep(50)
    let Joined(name) = ev
    log.push("welcome " + name)
  })
  let all = joined.add((_, ev) => {
    @aio.sleep(10)
    let Joined(name) = ev
    raise AuditClosed(name)
  })
  try all.publish_concurrent((), Joined("Ann")) catch {
    @mediator.PublishFailed(handlers~, failures~) as error => {
      assert_eq(handlers, 2)
      assert_eq(failures.length(), 1)
      guard failures.get(0) is Some(failure) else { fail("missing failure") }
      assert_eq(failure.position, 2)
      assert_true(failure.error is AuditClosed("Ann"))
      assert_eq(
        error.message(),
        "Publish failed: 1 of 2 handlers raised an error (position 2)",
      )
    }
    other => fail("publish raised another error: \{other}")
  } noraise {
    _ => fail("publish did not raise")
  }
  assert_eq(log, ["welcome Ann"])
}
```

## Cancellation and timeouts

A caller cancels a send or a publish through `moonbitlang/async`, for example
with `with_timeout_opt` around the call, or when the task group of the caller
ends. The mediator never catches, wraps, or counts a cancellation:

| Call | When the caller cancels it |
| --- | --- |
| `send` | The handler stops. The caller gets no reply and no mediator error |
| `publish` | The running handler stops and the remaining handlers do not start |
| `publish_concurrent` | Every running handler stops |

A cancellation is never a failure in `PublishFailed`. `catch` cannot capture a
cancellation, so a middleware that catches every error does not stop it. The
failures that a sequential publish held before the cancellation are not
reported. A caller that needs them publishes without a cancellation scope
around the publish. The `finally_` hook runs also during a cancellation.
A handler that reacts to its own cancellation with a protected cleanup, and
raises an ordinary error from it, gives that error from `send`, as a direct
call of the handler does. A publish does not start the next handler after a
cancellation and does not raise `PublishFailed` for it.

A time limit that a handler sets for itself, for example with
`with_timeout`, raises an ordinary error. `send` passes it out, and a publish
lists it as a failure and runs the other handlers.

`@mediator_async.timeout(limit)` takes a `@lander_core.TimeLimit`. Parse or
construct the limit once at the input boundary; zero and negative limits raise
`TimeLimitError` there. Replace a raw `timeout(50)` call with
`timeout(@lander_core.TimeLimit::millis(50))`. When the step does not end in time,
the middleware cancels it and raises `@mediator.TimedOut(after~)`, where `after`
is the same valid limit. Its message is `Request timed out after <milliseconds> ms`
and holds no request values. The shared limit is converted to milliseconds only
at the call to `moonbitlang/async`.

```mbt check
///|
#cfg(not(target="wasm-gc"))
async test "a timeout stops a slow send, and a caller cancellation is not an error" {
  let log = []
  let slow : @mediator_async.Sender[Unit, Ping, String] = @mediator_async.sender((
    _,
    req,
  ) => {
    @aio.sleep(1000)
    log.push("handler ended")
    let Ping(text) = req
    "Pong: " + text
  })
  let limited = slow.use_(@mediator_async.timeout(@lander_core.TimeLimit::millis(50)))
  try limited.send((), Ping("Hello")) catch {
    @mediator.TimedOut(_) as error =>
      assert_eq(error.message(), "Request timed out after 50 ms")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  let reply = @aio.with_timeout_opt(50, () => slow.send((), Ping("Hello")))
  assert_eq(reply, None)
  assert_eq(log, [])
}
```

## The context value and the core mediator

Each send and each publish takes a context value of type `C`. The mediator
gives that exact value to each middleware and to each handler, also after a
wait, and does not keep it after the call. A consumer service, such as the
Morphir workbench or moonrockz/smithy, puts its services in a record and
gives that record as the context.

The async package reuses the core error type `@mediator.MediatorError`, and it
works with core values in two ways:

| You have | Use | Result |
| --- | --- | --- |
| One sync handler | A one-line lambda: `@mediator_async.sender((c, r) => handle(c, r))` | An async sender. A named sync function does not fit an `async` function type, but the lambda does |
| A core `@mediator.Sender` | `@mediator_async.Sender::from_sync(sender)` | An async sender that runs the core middleware and handler, with the same reply and error |
| A core `@mediator.Topic` | `@mediator_async.Topic::from_sync(topic)` | An async topic whose publish runs the core publish and passes the core `PublishFailed` out unchanged |

After `add` on a wrapped core topic, the core publish counts as one handler at
position 1, and its error is the failure at that position. A core
`@mediator.Middleware` does not fit an async sender; use the async helpers.
There is no way to call an async sender from sync code.

```mbt check
///|
#cfg(not(target="wasm-gc"))
struct Store {
  users : Array[String]
}

///|
#cfg(not(target="wasm-gc"))
struct Services {
  store : Store
  greeting : String
}

///|
#cfg(not(target="wasm-gc"))
struct Register(String)

///|
/// A sync handler that the service already has.
#cfg(not(target="wasm-gc"))
fn greet(services : Services, req : Register) -> String {
  let Register(name) = req
  services.greeting + " " + name
}

///|
#cfg(not(target="wasm-gc"))
async test "a service registers a user and greets through the core sender" {
  let greeter : @mediator.Sender[Services, Register, String] = @mediator.sender((
    services,
    req,
  ) => greet(services, req))
  let greet_async = @mediator_async.Sender::from_sync(greeter)
  let register : @mediator_async.Sender[Services, Register, String] = @mediator_async.sender((
    services,
    req,
  ) => {
    @aio.sleep(10)
    let Register(name) = req
    services.store.users.push(name)
    greet_async.send(services, req)
  })
  let direct : @mediator_async.Sender[Services, Register, String] = @mediator_async.sender((
    services,
    req,
  ) => greet(services, req))
  let services = { store: { users: [] }, greeting: "Welcome" }
  assert_eq(register.send(services, Register("Ann")), "Welcome Ann")
  assert_eq(direct.send(services, Register("Bo")), "Welcome Bo")
  assert_eq(services.store.users, ["Ann"])
}
```
