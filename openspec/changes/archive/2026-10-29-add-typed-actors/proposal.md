# Proposal: Add local typed actors

## Why

Applications need long-lived state and work that processes one message at a
time. The mediator calls handlers in the caller's lifetime; it does not own an
actor, a mailbox or a receive loop. Provide local typed actors with the useful
capabilities of F# MailboxProcessor, Ox Actors and Kyo Actors, and simple startup
in the style of Gleam and Elixir.

## What Changes

- Add an optional `moonrockz/moon-lander-actors` module. Its portable root holds
  policy value types. Its `runtime` package uses `moonbitlang/async` on `wasm`,
  `js` and `native`, with the same target limit as the async mediator.
- Start an ordinary actor with an initial state and one handler. A scope owns
  its lifetime. No actor system, name, registry, trait implementation, builder
  chain or host setup is required.
- Provide typed message references, send, non-waiting send, request/reply and
  explicit reply destinations. Describe what an actor receives as `Receive`
  values that only the runtime runs, with combinators for sequences, selective
  receive, finite loops, state transitions, time limits, recovery and a result
  when an actor completes. A test can run a receive against a list of messages,
  with no scope or task.
- Add optional scope-reserved names and immutable typed directories for discovery.
  Directories support union, addition and removal by exact actor address.
  Each operation gives a new directory without changing actor ownership.
  Reusing a name must not redirect an old reference or address to a replacement.
- Provide bounded mailboxes with backpressure by default, an explicit unbounded
  option, time limits, cancellation, close, termination observation, cleanup
  and child lifetime ownership.
- Provide serialized invocation of a private service through closures, as in
  Ox. Provide automatic request/reply for a handler that returns a response.
- Provide typed message destinations and scoped publish/subscribe. Message
  mapping lets actors receive several event types through one protocol.
- Add runnable examples, acceptance tests, module validation and candidate
  archive checks. The new module participates in the existing release flow.

## Capabilities

### New Capabilities

- `actors`: local typed actors, state and receive entry points, mailbox
  policy, request/reply, serialized service calls, destinations, scoped event
  delivery, actor lifetimes, names, local addresses and algebraic typed directories.

### Modified Capabilities

- `framework-modules`: add the optional actors module, its dependency rules and
  shared version.
- `framework-publication`: include actors in the publication allowlist and
  verify its portable root and supported runtime targets through consumers.

## Tracking

Epic `lander-25h` holds one beads story per task group (`lander-25h.1` to
`lander-25h.9`). Story `lander-25h.2` also depends on release 0.7.0
(`lander-7ft`): module and publication integration starts after that release
lands on `main`. Actors are not part of release 0.7.0.

## Impact

- New module `pkgs/actors`, member of `moon.work`. It depends on core and the
  existing pin of `moonbitlang/async`. It does not depend on hosting,
  configuration, mediator or logging.
- No existing public API changes. Importing the umbrella does not require an
  actor scope or start actors. Actor use is an explicit standalone import.
- Implementation updates module/version validation, publication manifests,
  archive consumers, the docs index and agent module guidance for eight
  framework modules and ten published libraries. This proposal changes none
  of the toolchain pins.
- The first implementation group is a feasibility spike. It must compile the
  public examples and prove structured cleanup and selective receive before
  the remaining API is built.

## Out of scope

- Remoting, serialization, clustering, network identity and location transparency.
- Persistence, event sourcing and delivery across process failure.
- Full Akka, Pekko or OTP parity, automatic restart trees, hot code replacement,
  distributed registries and configurable dispatchers.
- Global string lookup, wildcard actor selection and automatic forwarding from
  an old address to a replacement actor.
- OS threads, parallel execution of a single actor, preemption and hard deadlines
  for code that never yields.
- A new effect system, a new event loop, UI integration and a blocking bridge
  that runs async actors on `wasm-gc`.
- Direct-style receive from any async code (the F# `inbox.Receive()` form).
  `Receive` values keep its capabilities.
- A scheduler and scheduled message sends. A later change adds them.
- Benchmarks in `mise run check`, CI or the release workflow. Benchmarks are a
  manual local task.
