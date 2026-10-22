# Design: Add the mediator

Labels: "Owner" marks a decision of the project owner. "Call" marks a
designer decision that the owner did not reject.

## Context

See proposal.md (Why). This section gives only the facts that shape the
design.

- MoonBit has no runtime reflection, no runtime type identity that user code
  can switch on, and no user source generators (probes with the pinned
  toolchain `moonc v0.10.15`, 2026-10-21). Handler discovery by naming
  convention, as Foundatio.Mediator does with C# source generators and
  interceptors, cannot port.
- MoonBit has generics, trait-bounded type parameters, first-class function
  values, labelled and optional arguments, `async fn`, and errors through
  `raise` with `suberror`. The repo uses these in `@config.bind`
  (`pub fn[T : FromJson] bind(...)`) and in the `|>` builder pipelines of
  the configuration core.
- The host lifecycle change (`add-host-lifecycle`) fixes the services model:
  no dependency-injection container. The application defines a typed
  services record `S`, the host builds it one time, and each command gets
  one immutable `Context[S]`. That change is not built yet (0 of 16 beads
  closed), so this design must not depend on it.
- MoonBit conditional compilation is target-only. Item-level
  `#cfg(target="...")` with `any`/`not`/`all` and `platform="..."` exists in
  the pinned toolchain (`moonbitlang/async` uses it), file-level gating
  exists through `options(targets: {...})` in `moon.pkg`, and a package can
  declare `supported_targets`. There is no user-defined cfg flag.
- Probe findings (scratch module outside the repo, all four targets,
  2026-10-21): a `#cfg(not(target="wasm-gc"))` async API next to a
  `wasm-gc` sync API builds and tests green, but `moon info --target
  wasm-gc` reports diverging interfaces across backends. An ungated
  suspending `async fn` builds on `wasm-gc`, but `moon test --target
  wasm-gc` runs zero tests and exits green (`no test entry found`). The
  `%async.run` intrinsic can drive an `async` handler from sync code on
  `wasm-gc`, only for handlers of type `async (Req) -> Res noraise +
  nocancel`; the compiler rejects a handler that suspends at a
  cancellation point.

## Goals / Non-Goals

**Goals:**

- One synchronous mediator core with the same public API and the same
  behavior on `wasm`, `wasm-gc`, `js`, and `native`.
- Compile-time proof that each send has exactly one handler and that
  request, reply, and context types match. No runtime lookup, no text keys.
- Near-direct-call cost: a send is a call through function values that the
  compiler monomorphizes.
- A middleware pipeline with fixed order and short-circuit, shared by send
  and publish, in the `|>` style of the rest of the framework.
- No dependency on `@hosting`, on `moonbitlang/async`, or on any host
  adapter. The package is pure.

**Non-Goals:**

- No async API in this change (see D5).
- No handler discovery, no text-key registry, no dependency-injection
  container, no cascading or streaming contract, no generated endpoints.
- No change to the context type of the host lifecycle. The mediator takes
  the context type as a generic parameter (D4).

## Decisions

### D1. Typed sender values, not a registry (Owner)

Registration takes a handler function and gives back a typed sender value.
The caller keeps the value and sends through it.

```moonbit
pub struct Sender[C, Req, Res] {
  handle : (C, Req) -> Res raise
  // middleware chain, see D3
}

pub fn[C, Req, Res] sender(
  handle : (C, Req) -> Res raise,
) -> Sender[C, Req, Res]

pub fn[C, Req, Res] Sender::send(
  self : Sender[C, Req, Res],
  ctx : C,
  req : Req,
) -> Res raise
```

- A handler is `(C, Req) -> Res raise`. The `raise` with no named error is
  MoonBit's general error effect: a handler can raise `MediatorError` or an
  application error, and `send` passes it through (spec: "Handler errors
  pass through send").
- The compiler monomorphizes `Sender[C, Req, Res]` per use. A send inlines
  to a direct call through the stored function value. There is no map, no
  key, and no dispatch table. This is the same end state that Foundatio
  reaches with interceptors, by language means instead of code generation.
- Call: value names follow Foundatio terms that users search for — `send`
  for one handler, `publish` for many. Request/reply types are named `Req`
  and `Res`, as in `@config` generic code.
- Alternative: one mediator value that holds every handler. Rejected. One
  value cannot hold handlers of many message types without runtime type
  identity, which MoonBit does not give user code.
- Alternative: registration under a text key with an untyped value.
  Rejected by the owner for the core. It gives up the compile-time proof,
  which is the main gain of this design over the .NET original. It can be
  added later at an embedder boundary without a core change.
- Alternative: one application-owned message enum with one `match`.
  Rejected as the core. It closes the message set to one package. An
  application that wants a closed set can still build it on top of D1
  senders.

### D2. Publish is a topic value with add composition

```moonbit
pub struct Topic[C, Ev] {
  handlers : Array[(C, Ev) -> Unit raise]
  // middleware chain, see D3
}

pub fn[C, Ev] topic(handle : (C, Ev) -> Unit raise) -> Topic[C, Ev]
pub fn[C, Ev] Topic::add(
  self : Topic[C, Ev],
  handle : (C, Ev) -> Unit raise,
) -> Topic[C, Ev]
pub fn[C, Ev] Topic::publish(self : Topic[C, Ev], ctx : C, ev : Ev) -> Unit raise
```

- Call: a topic starts with one handler, so an empty topic is not a value.
  `add` gives a topic with one more handler at the end; the topic value
  itself does not change (immutable public values, as in the rest of the
  framework). Publish runs handlers in add order and stops at the first
  error (spec: "A publish handler error stops publish"). That choice makes
  publish deterministic and testable. A run-all-then-report policy is a
  different contract; it is not in this change.
- Call: event handlers give `Unit`. An event has no reply. A caller that
  needs a reply uses `send`.
- No dynamic subscription. A topic is a value the application builds.
  Foundatio's `SubscribeAsync` over arbitrary types needs runtime type
  identity and is out of scope.

### D3. Middleware is a pipeline of wrappers (Owner: sync first)

```moonbit
pub struct Middleware[C, Req, Res] {
  wrap : ((C, Req) -> Res raise, C, Req) -> Res raise
}

pub fn[C, Req, Res] Sender::use_(
  self : Sender[C, Req, Res],
  middleware : Middleware[C, Req, Res],
) -> Sender[C, Req, Res]
```

- `Sender::use_` gives a new sender value; the sender itself does not
  change. The first `use_` is the outermost step (spec: "Middleware order
  is fixed"). Topic gets the same two steps with `Ev` and `Unit`.
- A middleware gets the next step as a function value. It can run code
  before and after the call, change the request or the reply, give a reply
  without a call (short-circuit), or catch an error from the next step and
  handle it. `Before`/`After`/`Finally` helper constructors cover the
  common Foundatio hooks on top of this one shape; the core needs only the
  wrapper shape. Helper constructors are part of task group 2.
- Middleware for a sender and middleware for a topic are the same shape
  with different `Req`/`Res`. Cross-type middleware (for example a logger
  for every message type) needs a middleware that is generic over the
  message; MoonBit function values are monomorphic per instantiation, so
  the application instantiates a logger per sender. That is one line per
  sender and it stays typed. A type-erased middleware is out of scope.
- Errors: a middleware can catch the error of the next step. It cannot
  turn an error into a reply unless it catches it. No implicit conversion.

### D4. The context is a generic value, passed unchanged (Owner)

- `C` is a plain generic parameter. The core stores no context and knows
  no field of it. `send` and `publish` take the context value from the
  caller and give the same value to each middleware and to the handler.
- When `add-host-lifecycle` lands, `C` can be its `Context[S]`, and a
  handler reads `ctx.services`, binds `ctx.config`, and calls
  `ctx.check_cancelled()`. That wiring is a later hosting step, in the
  host change or a small later mediator change. This change ships with
  `C = Unit` and with record contexts in its tests.
- Alternative: fix the context to the host `Context[S]` now. Rejected.
  The host is not built; the mediator would take a dependency on a planned
  package and could not be used without it.

### D5. Sync first; async is a later separate package (Owner)

- The core package contains only synchronous function values. It uses no
  `#cfg`, no per-target file, and no `options(targets: ...)` gating. The
  public interface is one interface on all four targets, so `moon info`
  shows no divergence and the checked interface file stays single.
- Async handlers are a later change: a package
  `moonrockz/moon-lander/mediator/async` (`@mediator_async`) with
  `supported_targets = "wasm+js+native"`, in the style of `config/host`
  (`supported_targets = "native+js"`) and `config/browser`
  (`supported_targets = "js"`). It will offer async senders and topics
  whose handlers are `async fn`. It will not change the core package.
  Note: the `wasm` leg of that package needs an embedder that supplies the
  `moonbitlang/async` event-loop imports, the same limit the host design
  records for `wasm`.
- The `wasm-gc` blocking adapter over `%async.run` is out of this change
  (proposal, Out of scope). The probe shows it works for
  `noraise + nocancel` handlers, but its error shape fights the `raise`
  handler model of D1, and `%async.run` is a compiler intrinsic, not a
  public API. It can be added later in one gated file without a core
  break.
- Test rule from the probe: an async test gated with `#cfg` would not run
  on `wasm-gc`. This change has no async tests. The integration task
  still verifies that each target leg of the mediator acceptance suite
  runs more than zero tests (spec: "Same behavior on all targets"), so a
  future gating change cannot pass on an empty leg in silence.

### D6. Errors are one suberror; the pipeline adds no hidden conversion

```moonbit
pub suberror MediatorError {
  // filled in by task group 1; at minimum a case for a middleware
  // that ends a call with no reply where a reply is owed is NOT a case:
  // short-circuit gives a reply value, so no such case exists.
}
```

- Call: task group 1 fixes the exact cases. The design constraint is that
  the core itself has almost no runtime failure modes: there is no missing
  handler (D1 makes it a compile error), no lookup, and no I/O. The
  realistic core-raised case is a contract fault in a helper constructor
  (for example an empty middleware list where the API requires one).
  Handler and application errors pass through as themselves. If group 1
  finds no core-raised case, it ships `MediatorError` with the cases it
  can name and test, and no more.
- Error text must not hold request field values. Requests can hold
  secrets; the core never formats a request. This follows the binding
  rule that error text does not show configured values
  (`add-configuration-binding`, group 3).

### D7. Package layout and naming

- Package `moonrockz/moon-lander/mediator` in `pkgs/lander/mediator`,
  imported as `@mediator`. Same module as `config` and the planned
  `hosting`; no new entry in `moon.work`, no new dependency in
  `pkgs/lander/moon.mod`.
- Files follow the `config` package shape: the core in `mediator.mbt`,
  middleware in `middleware.mbt`, publish in `topic.mbt`, errors in
  `error.mbt`, tests in `*_test.mbt` and `*_wbtest.mbt`, a runnable
  `README.mbt.md`, and the generated `pkg.generated.mbti` checked by
  `moon info`.
- Acceptance suites go in the unpublished `tests/` module as
  `tests/mediator-acceptance`, in the style of `tests/config-acceptance`.

## Risks / Trade-offs

- [A sender per message type is more values to hold than one `IMediator`]
  → The services record `S` of the host lifecycle is the natural home for
  senders; the application builds them in its services factory. Tests
  build one sender in one line.
- [No cross-type middleware] → A logger is instantiated per sender. One
  line each, fully typed. A type-erased middleware can be added later if
  a consumer shows the need.
- [Publish stops at the first error] → Deterministic and simple. A topic
  that must run all handlers puts the error-prone handler last or catches
  inside the handler. A run-all policy is a later contract change.
- [Users who know Mediatr or Foundatio expect discovery and a registry]
  → The README states the difference up front: registration is explicit,
  and the compiler is the registry. The Ping example shows the full
  wiring in a few lines.
- [The async package will duplicate the pipeline shape] → It shares the
  middleware ideas, not the core types. Duplication is small and keeps
  the core interface identical on every target, which D5 puts first.

## Migration Plan

No migration. This is a new package; no existing API changes. Rollback is
removal of `pkgs/lander/mediator` and of `tests/mediator-acceptance`.

## Open Questions

- Exact `MediatorError` cases (D6). Task group 1 names and tests them;
  the answer cannot change the specs, because the specs require only that
  handler errors pass through and that the core raises typed errors.
- Whether `Sender::use_` takes a `Middleware` value or a plain function.
  Task group 2 decides from the compiled doc example; both forms keep the
  spec contract (fixed order, short-circuit).
