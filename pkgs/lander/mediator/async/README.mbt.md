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
  "moonrockz/moon-lander/mediator/async" @mediator_async,
  "moonbitlang/async" @async,
}
```

| Target | Supported | Note |
| --- | --- | --- |
| `native`, `js` | Yes | |
| `wasm` | Yes | The host must supply the `moonbitlang/async` event-loop imports. `moonrun` supplies them for tests |
| `wasm-gc` | No | `moonbitlang/async` has no event loop there. Use the sync `@mediator` |

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
struct Ping(String)

///|
async test "send a ping to a handler that waits" {
  let ping : @mediator_async.Sender[Unit, Ping, String] = @mediator_async.sender((
    _,
    req,
  ) => {
    @async.sleep(10)
    let Ping(text) = req
    "Pong: " + text
  })
  assert_eq(ping.send((), Ping("Hello")), "Pong: Hello")
}
```

A sender calls its one handler one time for each send. An error that the
handler raises passes out of `send` unchanged. The mediator does not turn an
error into a reply.
