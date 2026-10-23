# Proposal: Add the async mediator

## Why

The core mediator (`@mediator`) is synchronous, so a handler cannot do I/O
or wait. The main consumers need async handlers: the Morphir workbench
service already runs on `moonbitlang/async` with task groups, and
moonrockz/smithy will integrate the mediator too. The host lifecycle that is
planned in `add-host-lifecycle` is also async: its hooks are `async` and a
stop request cancels the command task. An async mediator lets these
components talk through messages and keeps cancellation and timeouts in one
pipeline.

## What Changes

- Add the package `moonrockz/moon-lander/mediator/async` (`@mediator_async`)
  in `pkgs/lander`, with `supported_targets = "wasm+js+native"`. The core
  package `@mediator` keeps its sync API and its single interface on all
  four targets.
- Add async typed senders: a handler is an `async` function of the context
  and the request. The compiler fixes the context, request and reply types.
  There is no registration by text key and no runtime lookup.
- Add async topics with two publish operations, both in the Foundatio model
  of `change-mediator-publish-policy`:
  - `publish` runs the handlers one at a time, in add order.
  - `publish_concurrent` runs all handlers at the same time and waits for
    all of them.
  Both raise one `MediatorError::PublishFailed` that lists every failure in
  add order. No operation returns before its handlers end; there is no
  fire-and-forget publish.
- Cancellation: when the caller cancels a send or a publish, the running
  handlers stop, the remaining handlers do not run, and the cancellation
  passes out unchanged. It is never a failure in `PublishFailed`. A timeout
  inside a handler is an ordinary failure.
- Add an async middleware pipeline with the same helper names and order rule
  as the core: `middleware`, `before`, `after`, `finally_`. The `finally_`
  hook is a sync function, so it also runs during a cancellation.
- Add a `timeout(ms)` middleware. It cancels the next step when the time
  ends and raises the new core case `MediatorError::TimedOut(after_ms~)`.
- Reuse `@mediator.MediatorError`. Add `Sender::from_sync` and
  `Topic::from_sync`, which wrap a core sender or topic, with its
  middleware, as an async one.
- Document the package with runnable examples, add an acceptance suite in
  the unpublished `tests/` module, and extend `check:mediator` to the async
  package.

## Capabilities

### New Capabilities

- `mediator-async`: async typed senders and topics, sequential and
  concurrent publish with combined failures, caller cancellation, the
  timeout middleware, the async middleware pipeline, interop with the core
  mediator, and the same behavior on `wasm`, `js` and `native`.

### Modified Capabilities

None. The core package gets one new error case, `TimedOut`, which only the
async timeout middleware raises; the `mediator` requirements do not change.

## Impact

- New package `pkgs/lander/mediator/async`. It imports
  `moonrockz/moon-lander/mediator` and `moonbitlang/async`, which are
  already in the module. No new module and no new dependency.
- `pkgs/lander/mediator/error.mbt` gets the case `TimedOut(after_ms~)`.
  `MediatorError` is `pub(all)`, so this is a source break for exhaustive
  matches; it ships in the same `0.3.0` release as the publish policy
  change.
- The `wasm` leg of the package needs an embedder that supplies the
  `moonbitlang/async` event-loop imports. `moonrun` supplies them, so the
  tests run on `wasm`. `wasm-gc` is not supported.
- `scripts/check-mediator.mbtx` learns the targets of each path, so it
  checks the async package on `wasm`, `js` and `native` only.
- Depends on `change-mediator-publish-policy`, which adds
  `MediatorError::PublishFailed`.

## Out of scope

- A blocking adapter that runs async handlers from sync code on `wasm-gc`
  (`%async.run`). The core gets no async API and no `#cfg`.
- Calling an async sender from the sync core.
- A fire-and-forget publish, retries, rate limits and circuit breakers.
- Hosting integration (a builder step and `Context[S]` as the context
  type). It comes after `add-host-lifecycle`.
- Cascading and streaming handlers, handler discovery, text-key registries.
