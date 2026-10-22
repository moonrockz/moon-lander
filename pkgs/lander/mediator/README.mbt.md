# Mediator

The `mediator` package (`@mediator`) lets the parts of a MoonBit application
talk through messages instead of direct calls. It follows the mediator pattern
of [Foundatio.Mediator](https://github.com/FoundatioFx/Foundatio.Mediator), with
one important difference: registration is explicit, and the compiler is the
registry. There is no handler discovery, no text key, and no runtime lookup.

Import `moonrockz/moon-lander/mediator` as `@mediator`. The package is pure and
synchronous, so it has the same API and the same behavior on `wasm`, `wasm-gc`,
`js`, and `native`. Each `mbt check` block on this page runs as a test with
`mise run test`.

## Send a request

A handler is a function that takes a context value and a request, and gives a
reply. `@mediator.sender` takes the handler and gives a `Sender[C, Req, Res]`
value. Keep the value, and send each request through it.

| Type parameter | Meaning |
| --- | --- |
| `C` | The context value that the caller gives to each send |
| `Req` | The request type. A request of another type does not compile |
| `Res` | The reply type of the handler |

```mbt check
///|
struct Ping(String)

///|
test "send a ping" {
  let ping : @mediator.Sender[Unit, Ping, String] = @mediator.sender((_, req) => {
    let Ping(text) = req
    "Pong: " + text
  })
  assert_eq(ping.send((), Ping("Hello")), "Pong: Hello")
}
```

A sender calls its one handler one time for each send. No other handler runs.
When the application does not build a sender for a request type, no value can
send that request type, so the gap is a compile error and not a runtime error.

## Publish an event

A topic sends one event to many handlers. `@mediator.topic` takes the first
event handler and gives a `Topic[C, Ev]` value, so a topic always has at least
one handler. `Topic::add` gives a new topic with one more handler at the end.
`Topic::publish` calls each handler one time, in add order. An event has no
reply: publish gives `Unit`. A caller that needs a reply uses a sender.

```mbt check
///|
struct Joined(String)

///|
test "publish to two handlers" {
  let log = []
  let joined : @mediator.Topic[Unit, Joined] = @mediator.topic((_, ev) => {
    let Joined(name) = ev
    log.push("welcome " + name)
  })
  let all = joined.add((_, ev) => {
    let Joined(name) = ev
    log.push("count " + name)
  })
  all.publish((), Joined("Ann"))
  assert_eq(log, ["welcome Ann", "count Ann"])
}
```

Publish stops at the first handler that raises, and raises that error. The
handlers after it do not run for that publish. A topic that must run all
handlers catches the error inside the handler.

## Middleware

A middleware wraps the next step of a send or a publish. It gets `next`, the
context value, and the request or event. It can run code before and after
`next`, change the request or the reply, give a reply without a call to `next`,
or catch the error of `next`.
Cross-cutting work such as logs, validation, and timing goes in middleware, not
in handlers.

`Sender::use_` gives a new sender with one more middleware, and `Topic::use_`
does the same for a topic. The value that you start from does not change. A
topic middleware wraps the whole publish: its `next` runs all handlers. The
first middleware that you attach is the outermost step, so it runs first on the
way in and last on the way out.

| Constructor | Runs |
| --- | --- |
| `@mediator.middleware(wrap)` | `wrap(next, ctx, req)`, which gives the reply |
| `@mediator.before(hook)` | `hook(ctx, req)` before the next step |
| `@mediator.after(hook)` | `hook(ctx, req, reply)` after the next step gives a reply |
| `@mediator.finally_(hook)` | `hook(ctx, req)` after the next step, also when it raises |

```mbt check
///|
test "log middleware around a send" {
  let log = []
  let ping : @mediator.Sender[Unit, Ping, String] = @mediator.sender((_, req) => {
    log.push("handler")
    let Ping(text) = req
    "Pong: " + text
  })
  let logged = ping
    .use_(
      @mediator.middleware((next, ctx, req) => {
        log.push("log in")
        let reply = next(ctx, req)
        log.push("log out")
        reply
      }),
    )
    .use_(@mediator.after((_, _, reply) => log.push("reply " + reply)))
  assert_eq(logged.send((), Ping("Hello")), "Pong: Hello")
  assert_eq(log, ["log in", "handler", "reply Pong: Hello", "log out"])
}
```

Middleware is typed like the sender: a `Middleware[C, Req, Res]` fits only a
sender with the same three types. To log every message type, make one
middleware value for each sender.

## The context value

Each send and each publish takes a context value of type `C`. The mediator
gives that exact value to each middleware and to the handler. It does not copy
the value, change it, or keep it after the call. The mediator does not know
what `C` holds, so a context can be `Unit`, or a record that holds the services
of the application.

```mbt check
///|
struct Services {
  greeting : String
}

///|
struct AppContext {
  services : Services
}

///|
test "a handler reads the services from the context" {
  let ping : @mediator.Sender[AppContext, Ping, String] = @mediator.sender((
    ctx,
    req,
  ) => {
    let Ping(text) = req
    ctx.services.greeting + ": " + text
  })
  let ctx = { services: { greeting: "Pong", }, }
  assert_eq(ping.send(ctx, Ping("Hello")), "Pong: Hello")
}
```

## Errors

The mediator raises no error of its own. A missing handler is a compile error,
and there is no lookup and no I/O. A handler or a middleware can raise an
error. `send` and `publish` raise the same error and give no reply, unless a
middleware catches it. The mediator does not turn an error into a reply.

`MediatorError` holds the failures that belong to the mediator pattern. Its one
case, `Rejected(reason~)`, is for a handler or a middleware that refuses a
request, for example after validation. `MediatorError::message` gives the text
for people. It holds only the reason, because a request can hold secrets. An
application error passes through as itself.

```mbt check
///|
test "a validation middleware rejects a request" {
  let ping : @mediator.Sender[Unit, Ping, String] = @mediator.sender((_, req) => {
    let Ping(text) = req
    "Pong: " + text
  })
  let checked = ping.use_(
    @mediator.before((_, req) => {
      let Ping(text) = req
      if text == "" {
        raise @mediator.Rejected(reason="the ping text is empty")
      }
    }),
  )
  try checked.send((), Ping("")) catch {
    @mediator.Rejected(_) as error =>
      assert_eq(error.message(), "Request rejected: the ping text is empty")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
  assert_eq(checked.send((), Ping("Hello")), "Pong: Hello")
}
```
