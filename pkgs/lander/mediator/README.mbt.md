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
> typed senders. Middleware, publish to many handlers, and typed errors come
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
