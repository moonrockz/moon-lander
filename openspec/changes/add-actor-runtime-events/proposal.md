# Proposal: Add actor runtime events

## Why

The actors runtime does not tell anyone what it does. When a message is not
delivered, only the sender sees it, and only for `try_send` and a closed `send`.
Messages that stop, cancel or failure discard are lost with no trace. Tests must
poll `status()` to see an actor end. Akka and Pekko solve this with the
`EventStream`, one bus for each actor system where the runtime publishes dead
letters and lifecycle events. Moon-Lander needs the same visibility, without a
global bus and with typed events.

## What Changes

- Add a `RuntimeEvents` value. A scope that gets one with `scope(events~)`
  publishes typed `ActorEvent` values to it. Without it, a scope publishes
  nothing and does no extra work. Child scopes of actors use the same value.
- Events: an actor started, an actor ended (with its `ActorEnd`), and a message
  was not delivered (full, closed or discarded), with an optional payload.
- The runtime never waits for an event subscriber and is never failed by one.
  When a subscriber is full, the runtime drops the event for that subscriber and
  counts it. Events about the delivery of runtime events are never published.
- Application code cannot publish a runtime event: `RuntimeEvents` has no
  public publish operation. The existing `Topic[M]` stays for application events.
- Payloads use the Amazon Ion data model from `moonrockz/ion`. A new
  `PayloadPolicy[M]` selects the payload for each actor: `omit` (the default),
  `ion` for a protocol with `ToIon`, `json` as a bridge for a protocol with core
  `ToJson`, and `encode` for a custom or redacted form.
- The actors module imports `moonrockz/ion` (the `ion` data-model package only),
  at the version that `moonrockz/moon-lander-config` already uses.

## Capabilities

### New Capabilities

- `actor-runtime-events`: the runtime event channel of actor scopes, its event
  set, non-waiting delivery, subscriptions and the message payload policy.

### Modified Capabilities

- `framework-modules`: the actors module can import `moonrockz/ion` in addition
  to `moonbitlang/async`.

## Tracking

Proposed on 2026-10-30, from the owner's request to give Moon-Lander the useful
part of the Akka and Pekko `EventStream`, with Ion as the payload format. The
owner approved the change and its Call decisions on 2026-10-31 (PR #146). Epic
`lander-d0y` holds stories `lander-d0y.1` to `lander-d0y.4`.

A separate workspace adds `FromIon` and codec parity to `moonrockz/ion`. This
change does not depend on that work: it uses only `ToIon` and
`impl ToIon for Json`, which `moonrockz/ion` 0.6.0 has.

## Impact

- `pkgs/actors`: the portable root gets `PayloadPolicy`; the runtime gets
  `RuntimeEvents`, `ActorEvent`, `Undelivered`, `EventSubscription`, an optional
  `events` argument on `scope` and an optional `payload` argument on `start`,
  `start_with`, `spawn` and `respond`. These additions do not change existing
  calls.
- `pkgs/actors/moon.mod` imports `moonrockz/ion@0.6.0`.
  `scripts/validate-packages.mbtx` allows that import for actors.
- No change to the other framework modules, the umbrella or the publication
  order. `moonrockz/ion` is already published, so no new publication step is
  necessary.
- Documentation: runnable examples for a dead-letter counter, a test that waits
  for an `Ended` event, and a bridge from events to a logger.

## Out of scope

- A process-global event bus, subscription by type or class, and a registry.
- Events for replies to an expired or answered `Reply`, for custom `Subject`
  destinations that have no actor address, and for topic publications.
- A dependency from actors to logging, or from logging to actors or Ion.
- Decoding of payloads (`FromIon`), payload schemas and payload persistence.
- Remote, durable or replayed events, and delivery across a process failure.
- Supervision or restart decisions that use events.
