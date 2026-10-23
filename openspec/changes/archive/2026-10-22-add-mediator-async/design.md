# Design: Add the async mediator

Labels: "Owner" marks a decision of the project owner. "Call" marks a
designer decision that the owner did not reject. The owner reviewed and
accepted every recommendation below on 2026-10-23.

## Context

See proposal.md (Why). Facts that shape the design, from probes with the
pinned toolchain (`moonc v0.10.17`, `moonbitlang/async@0.22.5`, 2026-10-23,
scratch module outside the repo) and from the pinned library source:

- An `async` function type accepts an inline lambda, but not a named sync
  function, also when that function has no `raise`
  (`has type (Unit, Int) -> Int`, `wanted async (...)`). A one-line wrapper
  lambda `(c, r) => f(c, r)` works on `native`, `js` and `wasm`.
- An `async fn` can raise with no `raise` annotation.
- `moonbitlang/async` says in `async.mbt`: "`catch` can no longer capture
  cancellation, and cancellation is no longer represented as an error".
  `handle_cancellation` can react to a cancellation but "cannot be used to
  revert cancellation". A probe confirmed that a `catch` around a cancelled
  wait does not run.
- `with_timeout(time, f, error~)` cancels `f` when the time ends and raises
  `error` (default `TimeoutError`, an ordinary error).
- `with_task_group` returns only after every child task ends. A child that
  fails makes the group fail and cancels the other children, unless the
  child is spawned with `allow_failure=true`.
- Async tests run on `native`, `js` and `wasm` (`moonrun` supplies the
  event-loop imports). On `wasm-gc` the runner reports "no test entry
  found" and runs zero tests.
- moonspec step handlers are synchronous (`() -> Unit raise Error`), so a
  step cannot await an async send.
- The core mediator (`@mediator`) after `change-mediator-publish-policy`:
  abstract `Sender`, `Topic`, `Middleware`; `publish` runs every handler and
  raises `MediatorError::PublishFailed(handlers~, failures~)`.

## Goals / Non-Goals

**Goals:**

- The same shape as the core: typed values, no registry, the same helper
  names and order rule, the same publish contract.
- Structured concurrency: no task outlives the call that started it.
- Cancellation and timeouts that compose with the planned host lifecycle
  without a dependency on it.

**Non-Goals:**

- Any change to the sync API of `@mediator` other than one new error case.
- A `wasm-gc` leg (see proposal, Out of scope).

## Decisions

### D1. A separate package with explicit targets (Owner, from add-mediator D5)

- Package `moonrockz/moon-lander/mediator/async` in
  `pkgs/lander/mediator/async`, imported as `@mediator_async`, with
  `supported_targets = "wasm+js+native"`. It imports `@mediator` and
  `moonbitlang/async`.
- No `#cfg` and no per-target file. Moon writes `pkg.generated.mbti` only
  from the module's canonical backend (`wasm-gc` here), so this package gets
  no interface file, the same as `config/host` and `config/browser`. The
  owner accepted this limit on PR #50 (option A). Task group 6 compares the
  `moon info --target` reports for `wasm`, `js` and `native` instead.

### D2. Types mirror the core (Call)

```moonbit
struct Sender[C, Req, Res] {
  handle : async (C, Req) -> Res
  middleware : Array[Middleware[C, Req, Res]]
}
struct Middleware[C, Req, Res] {
  wrap : async (async (C, Req) -> Res, C, Req) -> Res
}
struct Topic[C, Ev] {
  handlers : Array[async (C, Ev) -> Unit]
  middleware : Array[Middleware[C, Ev, Unit]]
}
```

- The types are abstract, as in the core, so no caller can skip the
  middleware. `use_`, `add` and the constructors give new values; no value
  changes after it exists.
- The names match the core (`sender`, `topic`, `Sender::send`,
  `Sender::use_`, `Topic::add`, `Topic::use_`, `Topic::publish`), so the two
  packages read the same.

### D3. Sequential publish is the Foundatio `ForeachAwait` model (Owner)

- `publish` runs the handlers one at a time and catches the error of each
  one into a `PublishFailure` with its position. After the last handler it
  raises `PublishFailed` if any handler failed.
- `catch` cannot capture a cancellation, so a caller cancellation ends the
  loop at once and passes out unchanged. The failures that the loop held
  before the cancellation are not reported. The README states this.

### D4. Concurrent publish is the Foundatio `TaskWhenAll` model (Owner)

- `publish_concurrent` runs `with_task_group` and spawns one child per
  handler. Each child catches its own handler error into a slot for its
  position, so no child fails and the group does not cancel the others.
  After the group ends, the publish raises `PublishFailed` with the failures
  in add order.
- Alternative: `spawn_bg(allow_failure=true)` and read the task results.
  Rejected: the catch in the child keeps the order by position and needs no
  task handles.
- Alternative: the fail-fast default of the task group, as in Python's
  `asyncio.TaskGroup`. Rejected by the owner: the Foundatio model runs
  every handler.
- A caller cancellation cancels the group, so every child stops and the
  cancellation passes out.

### D5. No fire-and-forget (Owner)

- Foundatio's `FireAndForget` swallows errors, and `moonbitlang/async` lets
  no task outlive its group. There is no publish that returns before its
  handlers end. An application that wants background work starts its own
  task group.

### D6. Cancellation passes through; timeouts are errors (Owner)

- A caller cancellation is never caught, wrapped or counted (D3, D4). The
  library makes this the only possible behavior; it also matches Python's
  `TaskGroup`, which leaves `CancelledError` out of its `ExceptionGroup`,
  and the NServiceBus guidance to let cancellation propagate.
- A timeout that a handler sets for itself raises `TimeoutError` or its own
  error, which is an ordinary error, so a publish counts it as a failure.

### D7. The timeout middleware (Owner)

```moonbit
pub fn[C, Req, Res] timeout(after_ms : Int) -> Middleware[C, Req, Res]
```

- It calls `with_timeout(after_ms, next, error=MediatorError::TimedOut(after_ms~))`.
  The next step is cancelled when the time ends, and the caller gets a
  mediator error with no request values (rule D6 of add-mediator).
- `TimedOut(after_ms~)` is a new case of `@mediator.MediatorError`;
  `message` gives "Request timed out after N ms". Foundatio names timeouts
  as the main use of its `ExecuteAsync` hook but ships no helper; Python's
  `asyncio.timeout` has the same cancel-then-raise shape.

### D8. Hooks: async before and after, sync finally (Owner)

- `before` and `after` take async hooks. `after` runs only after a reply.
- `finally_` takes a sync hook and runs it in a `defer`, so it runs after a
  reply, after an error, and during a cancellation. An async hook would need
  `protect_from_cancel` to run during a cancellation. Foundatio's `Finally`
  "always runs, regardless of success or failure".

### D9. Interop with the core (Owner)

- Reuse `@mediator.MediatorError`; no new error type.
- `Sender::from_sync(@mediator.Sender)` and `Topic::from_sync(@mediator.Topic)`
  wrap a core value, with its middleware, through its public `send` or
  `publish`. A single sync handler needs no helper: a one-line lambda
  adapts it (Context, probe), and the README shows it.
- `Topic::from_sync` passes the core `PublishFailed` out unchanged, with the
  positions and the handler count of the core topic (Owner, 2026-10-22). The
  core topic does not give its handler count, so after `add` on a wrapped
  topic the core publish counts as one handler at position 1, and its error
  is the failure at that position.
- A core `Middleware` cannot wrap an async next step, because its `next` is
  sync, so the async package has its own `Middleware` type.
- The other direction (async from sync) is out of scope.

### D10. Tests and the zero-test gate (Call)

- Unit tests in the package and an acceptance suite in
  `tests/mediator-async-acceptance` (`supported_targets = "wasm+js+native"`)
  use plain `async test` blocks, one per spec scenario, because moonspec
  steps cannot await (Context).
- Timing scenarios use `@async.sleep` with wide margins (for example 10 ms
  against 1000 ms) and order logs, not clock reads, so they stay stable.
- `scripts/check-mediator.mbtx` gets a target list per path: the core paths
  on all four targets, the async paths on `wasm`, `js` and `native`. A leg
  with zero tests still fails.

## Risks / Trade-offs

- [Failures before a caller cancellation are lost] → The library cannot
  catch a cancellation. The README states it; a caller that needs them
  publishes without a cancellation scope around the publish.
- [Timing tests can be flaky] → Wide margins and order logs; no test
  compares clock values.
- [The `wasm` leg needs embedder imports] → `moonrun` supplies them for
  tests. The README states that a `wasm` host must supply the
  `moonbitlang/async` imports, as the host design records.
- [Two packages with the same names] → Callers import one alias per
  package (`@mediator`, `@mediator_async`), so there is no clash.

## Migration Plan

New package; no migration. Rollback is removal of
`pkgs/lander/mediator/async`, `tests/mediator-async-acceptance`, the
`TimedOut` case and the gate entries.
