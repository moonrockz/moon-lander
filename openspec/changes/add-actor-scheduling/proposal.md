# Proposal: Add actor scheduling

## Why

Actors often need work at a later time: a session that expires, a retry with a
growing delay, a poll every few seconds. Without framework support, each
application writes a sleep loop in its own task, outside the actor's lifetime,
and its tests must wait in real time. `add-typed-actors` gives every wait to the
runtime (its TEST-1 decision), so the framework can schedule messages and a test
can move time forward by hand.

## What Changes

- Route every runtime wait of the actors runtime through one internal clock:
  receive time limits, ask deadlines, cleanup budgets and timers. No public API
  of `add-typed-actors` changes.
- Add a deterministic test clock. The receive test runner and an actor scope can
  use it, so tests move time forward with no real waiting.
- Add `send_after`: a scope-owned, cancellable send of one message after a delay,
  with the names that Erlang, Elixir and Gleam use.
- Add repeated sends on pure `Schedule` values (fixed delay, exponential growth,
  a checked count limit). A test can list the delays of a schedule without a
  runtime.
- Add `send_repeated`: repeated sends on a schedule, each delay measured from the
  admission of the previous message.
- Add actor-owned timers with typed keys. A timer with an existing key replaces
  the old one. A message that a cancelled or replaced keyed timer already queued
  is never received. All timers of an actor stop when the actor ends.
- Timer sends follow the actor admission rules: they wait for space in a full
  mailbox, never drop or overwrite a message, and stop when the target closes.

## Capabilities

### New Capabilities

- `actor-scheduling`: scheduled and repeated message sends, schedule values,
  actor-owned keyed timers, the runtime clock boundary and the test clock.

### Modified Capabilities

None. The actors capability of `add-typed-actors` is not yet an accepted spec;
this change adds a separate capability that depends on it.

## Tracking

Approved for implementation on 2026-10-29, as a follow-up after
`add-typed-actors`. Epic `lander-8fh` holds stories `lander-8fh.1` to
`lander-8fh.4`. A release of both changes follows (`lander-yvv`).
Implementation depends on `add-typed-actors` groups 4 (receives and `within`) and
6 (lifetimes and cleanup), epic `lander-25h`.

## Impact

- `pkgs/actors` from `add-typed-actors`: the portable root gets `Schedule`; the
  runtime gets the clock boundary, the test clock, `send_after`, repeated sends
  and keyed timers. No new module and no new dependency: timers use the existing
  `moonbitlang/async` pin.
- No change to other framework modules, the umbrella, or publication rules.
- Documentation: runnable examples for each send form and for tests with the test
  clock.

## Out of scope

- Fixed-rate schedules that try to catch up after a delay. Only fixed delay is in
  scope, so ticks never pile up behind backpressure.
- Jitter and other schedules that need randomness.
- Calendar or cron schedules, time zones and wall-clock dates.
- Durable timers that survive a process restart, and distributed scheduling.
- A global scheduler or timer service outside actor scopes.
- Hard real-time guarantees. Timers are cooperative and can fire late when a
  handler does not yield.
