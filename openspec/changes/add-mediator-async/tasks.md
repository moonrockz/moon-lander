# Tasks: add-mediator-async

Epic: lander-4us.19

This change adds the package `moonrockz/moon-lander/mediator/async` in
`pkgs/lander/mediator/async` with `supported_targets = "wasm+js+native"`. It
depends on `change-mediator-publish-policy` (`MediatorError::PublishFailed`).
It must contain no `#cfg` and no per-target file, and it must not change the
sync API of `@mediator` other than the new case `TimedOut`. Run each test on
`wasm`, `js` and `native`; the core tests still run on all four targets.
`check:mediator` fails a target leg that runs zero mediator tests.

## 1. Tracer bullet: one async sender, one request, one reply

Bead: lander-4us.19.1

- [ ] 1.1 Create `pkgs/lander/mediator/async` (`moon.pkg` with `supported_targets = "wasm+js+native"`, imports `moonrockz/moon-lander/mediator` and `moonbitlang/async`); verify `mise run build` passes and the package builds on `wasm`, `js` and `native`
- [ ] 1.2 Add the abstract `Sender[C, Req, Res]`, `sender` and `Sender::send` of design D2 with the handler type `async (C, Req) -> Res`; verify an async test sends `Ping("Hello")` through a handler that waits, gets `"Pong: Hello"`, and the handler runs one time
- [ ] 1.3 Verify an async handler error passes out of `send` unchanged, and record in a test comment the compile error for a request of the wrong type
- [ ] 1.4 Give `scripts/check-mediator.mbtx` a target list per path (core paths: four targets; async paths: `wasm`, `js`, `native`) and add the async package; verify its script test still fails on a zero-test leg and `mise run check:mediator` passes
- [ ] 1.5 Add the Ping example to the package `README.mbt.md`, with the note that a `wasm` host must supply the `moonbitlang/async` imports; verify the example runs in `mise run test` on `wasm`, `js` and `native`

## 2. Async middleware pipeline

Bead: lander-4us.19.2

- [ ] 2.1 Add the abstract async `Middleware[C, Req, Res]`, `middleware` and `Sender::use_` of design D2; verify `use_` gives a new sender and the original sender still sends without the middleware
- [ ] 2.2 Add `before` and `after` with async hooks, and `finally_` with a sync hook in a `defer` (design D8); verify a log records before, handler and after in order, and that `after` does not run when the next step raises
- [ ] 2.3 Verify the order rule (A then B gives A, B, handler, B, A), a middleware that replies without the next step (the handler does not run), and middleware that change the request and the reply
- [ ] 2.4 Verify a middleware that catches the error of the next step can give a reply, and one that does not catch passes the same error out
- [ ] 2.5 Document the async middleware with a runnable log example in the README; verify it runs on `wasm`, `js` and `native`

## 3. Async topics: sequential and concurrent publish

Bead: lander-4us.19.3

- [ ] 3.1 Add the abstract `Topic[C, Ev]`, `topic`, `Topic::add` and `Topic::use_`; verify `add` gives a new topic and the original keeps its handler count
- [ ] 3.2 Add `Topic::publish` as in design D3; verify three handlers run one at a time in add order (each starts after the previous one ends), that a failing second handler gives one `PublishFailed` at position 2 of 3 after all three run, and that no failure gives no error
- [ ] 3.3 Add `Topic::publish_concurrent` as in design D4; verify two waiting handlers overlap (the second starts before the first ends), that publish returns after both end, and that failures appear in add order when the third handler fails before the first
- [ ] 3.4 Verify a topic middleware gets the one combined error from both publish operations and can catch it
- [ ] 3.5 Document both publish operations, the Foundatio model and the absence of fire-and-forget in the README with a runnable example; verify it runs on `wasm`, `js` and `native`

## 4. Cancellation and timeouts

Bead: lander-4us.19.4

- [ ] 4.1 Verify caller cancellation of `send` (with `with_timeout_opt` around the call): the handler stops, no reply and no mediator error, and the call ends as cancelled
- [ ] 4.2 Verify caller cancellation of a sequential publish during the second of three handlers: the second stops, the third does not start, no `PublishFailed`; and of a concurrent publish: both waiting handlers stop
- [ ] 4.3 Verify a handler that raises a timeout error from its own `with_timeout` is an ordinary failure: send passes it out, and a publish lists it and runs the other handlers
- [ ] 4.4 Add the case `MediatorError::TimedOut(after_ms~)` to `@mediator` with the `message` "Request timed out after N ms", and the `timeout(after_ms)` middleware of design D7; verify a 50 ms timeout stops a 1000 ms handler and raises `TimedOut` with 50, a 1000 ms timeout gives the reply of a 10 ms handler, and the core tests and `pkgs/lander/mediator/pkg.generated.mbti` show only the new case
- [ ] 4.5 Verify `finally_` runs one time when the caller cancels a send
- [ ] 4.6 Document cancellation (including that failures before a cancellation are not reported) and the timeout middleware in the README with a runnable example; verify it runs on `wasm`, `js` and `native`

## 5. Interop with the core and the context value

Bead: lander-4us.19.5

- [ ] 5.1 Add `Sender::from_sync` and `Topic::from_sync` of design D9; verify a wrapped core sender with a log middleware runs the core middleware and handler and gives the core reply, and a wrapped core topic raises the core `PublishFailed`
- [ ] 5.2 Verify the context value passes unchanged: a handler and a middleware read a services record field after a wait and see the value that the caller gave, also when the field changes between two sends
- [ ] 5.3 Document the one-line lambda for a sync handler, `from_sync`, and a services-record example in the shape of a consumer service (the Morphir workbench and moonrockz/smithy) in the README; verify it runs on `wasm`, `js` and `native`

## 6. Integration check, acceptance suite and docs

Bead: lander-4us.19.6

- [ ] 6.1 Add `tests/mediator-async-acceptance` (`supported_targets = "wasm+js+native"`) with one `async test` per spec scenario of `mediator-async`; verify `mise run test` passes on `wasm`, `js` and `native`
- [ ] 6.2 Add the acceptance suite to `check:mediator`; verify each async leg runs more than zero tests and record the counts per target in the bead
- [ ] 6.3 Verify the `moon info --target` reports for the async package are the same for `wasm`, `js` and `native`, the core interface is still the same on all four targets, and the package source has no `#cfg` and no per-target file
- [ ] 6.4 Add the async mediator row to the layer table in `pkgs/lander/README.md` and a row to `tests/README.md`; verify `mise run build:site` and `mise run check:site` pass
- [ ] 6.5 Add the async package and the new `TimedOut` case to the `## Unreleased` section of `CHANGELOG.md`; verify `mise run test:scripts` passes
- [ ] 6.6 Run `mise run check`; verify lint, validation, all target tests, `check:mediator` and builds pass

## Workflow follow-up

- Archive this change after it merges.
- Propose hosting integration (`Context[S]` as the context type, senders in the services record) after `add-host-lifecycle` lands.
- A `wasm-gc` blocking adapter over `%async.run` stays out of scope until a consumer needs it.
