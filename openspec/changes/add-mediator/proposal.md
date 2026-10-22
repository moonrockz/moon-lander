# Proposal: Add the mediator

## Why

MoonBit applications in this framework will grow into components that call each
other directly, as .NET applications do without a mediator. Foundatio.Mediator
(https://github.com/FoundatioFx/Foundatio.Mediator) shows the value of the
mediator pattern: every interaction flows through messages, so components stay
loosely coupled and easy to test. MoonBit has no runtime reflection and no
source generators, so the .NET discovery machinery does not port. The pattern
itself does: a handler is a typed function value, and a call through it is a
direct call with no runtime lookup.

finos/morphir-moonbit, the first consumer, wires each command by hand today:
each command connects its own stop flag, maps its own exit codes, and flushes
its own logs. A mediator with a middleware pipeline gives Morphir one place
for these cross-cutting steps when it moves onto the host lifecycle.

## What Changes

- Add the package `moonrockz/moon-lander/mediator` (`@mediator`) in
  `pkgs/lander`. It is a synchronous mediator core with the same public API on
  `wasm`, `wasm-gc`, `js`, and `native`.
- Add typed sender values. A registration step takes a handler function and
  gives back a `Sender[C, Req, Res]` value. `send` calls the one handler for
  that sender and gives its reply. The request type, reply type, and context
  type are generic parameters. No handler exists for a sender that the
  application did not build, and the compiler proves it.
- Add publish. A registration step takes one event handler and gives back a
  `Topic[C, Ev]` value. `add` composes more handlers onto a topic. `publish`
  calls each handler of the topic in registration order.
- Add a middleware pipeline. A middleware wraps the next step of a send or a
  publish. Middleware runs in a fixed order, can run code before and after the
  handler, can change the request or the reply, and can end the call without
  the handler. Cross-cutting work (log, validate, authorize, time) lives in
  middleware, not in handlers.
- Add a typed error type, `MediatorError`, as a `suberror`. A handler or a
  middleware raises it, or raises an application error that the pipeline
  passes through unchanged.
- Pass an explicit context value of type `C` through each send and publish.
  The core does not know what `C` holds. The host lifecycle can use its
  `Context[S]` as `C` in a later change.
- Document the package with runnable examples and add an acceptance suite in
  the unpublished `tests/` module.

## Capabilities

### New Capabilities

- `mediator`: typed synchronous request/response through sender values,
  publish to many handlers through topic values, a middleware pipeline with
  fixed order and short-circuit, explicit context passing, and typed errors,
  with the same behavior on all four targets.

### Modified Capabilities

None. This change does not change the requirements of `configuration-core`,
and it does not depend on the unbuilt `host-lifecycle` capability.

## Impact

- New package in the `moonrockz/moon-lander` module: `mediator` under
  `pkgs/lander`. No new module in `moon.work`. No new dependency: the core is
  pure MoonBit and needs no I/O, no `moonbitlang/async`, and no host adapter.
- The package interface is the same on `wasm`, `wasm-gc`, `js`, and `native`.
  The package uses no `#cfg` and no per-target file.
- Acceptance suites go in the unpublished `tests/` module. Each target leg
  must run more than zero tests for the mediator suite.
- finos/morphir-moonbit can later route each command through one sender, and
  move log flush, validation, and timing into middleware. That move is a
  later change in Morphir, not in this change.

## Out of scope

- An async mediator package. Async handlers are a later, separate package
  with `supported_targets = "wasm+js+native"`. The core package gets no async
  API and no `#cfg` target split in this change.
- A blocking adapter that drives async handlers on `wasm-gc` through the
  `%async.run` intrinsic. It can be added later without a core API break.
- Cascading messages (a handler that sends further messages as part of its
  contract) and streaming handlers.
- Convention discovery of handlers by name, registration by text key, and
  any registry that finds handlers at runtime. MoonBit has no reflection,
  and the compiler must prove each sender's handler exists.
- A dependency-injection container. The services record pattern of the host
  lifecycle stays the one way to hold services.
- Generated HTTP or UI endpoints. This framework has no user interface;
  Moonbase owns that layer.
- Hosting integration. No `@hosting` builder step in this change; the host
  lifecycle is not built yet. The generic context type `C` is the seam.
