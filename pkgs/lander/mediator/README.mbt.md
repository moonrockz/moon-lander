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

> [!NOTE]
> The mediator is in progress. This page shows the API that exists today:
> typed senders and middleware. Publish to many handlers and typed errors come
> in later task groups of the `add-mediator` change.

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

## Errors

A handler can raise an error. `send` raises the same error and gives no reply.
The mediator does not turn an error into a reply.

## Middleware

A middleware wraps the next step of a send. It gets `next`, the context value,
and the request. It can run code before and after `next`, change the request or
the reply, give a reply without a call to `next`, or catch the error of `next`.
Cross-cutting work such as logs, validation, and timing goes in middleware, not
in handlers.

`Sender::use_` gives a new sender with one more middleware. The sender that you
start from does not change. The first middleware that you attach is the
outermost step, so it runs first on the way in and last on the way out.

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
