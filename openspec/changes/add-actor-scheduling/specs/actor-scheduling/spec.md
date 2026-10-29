# Actor scheduling specification delta

## Purpose

Let actors receive messages at a later time, once or on a schedule, inside actor
lifetimes, and let tests control time without real waiting.

## ADDED Requirements

### Requirement: One runtime clock

Every wait of the actors runtime SHALL use one clock: receive time limits, ask
deadlines, cleanup budgets and timers. The default clock SHALL use real time. A
scope and the receive test runner SHALL accept a test clock instead.

#### Scenario: Receive time limit on the test clock

- **WHEN** a receive with a five-second time limit waits on a test clock and the test advances the clock by five seconds
- **THEN** the receive continues with its timeout receive, and no real time passes

#### Scenario: Ask deadline on the test clock

- **WHEN** an ask with a ten-second deadline waits in a scope that uses a test clock and the test advances the clock by ten seconds
- **THEN** the ask reports a typed timeout

### Requirement: Deterministic test clock

A test clock SHALL start at zero and change only when a test advances it. It MUST
NOT advance on its own, also when every task waits. Advancing it SHALL fire due
timers and expire due waits in deadline order, with ties in the order they were
scheduled.

#### Scenario: Ordered firing

- **WHEN** timers are due at three seconds and one second and the test advances the clock by five seconds
- **THEN** the one-second timer fires before the three-second timer

#### Scenario: No advance

- **WHEN** a timer is due at one second, every task waits, and the test does not advance the clock
- **THEN** the timer does not fire, however long the test runs

### Requirement: Scheduled send

A scope SHALL send one message to a typed destination after a time limit. The
result SHALL be a cancellable timer. Cancelling before the send SHALL prevent it.
The scope SHALL cancel its timers when it exits.

#### Scenario: Send after a delay

- **WHEN** a scope schedules Expire to a session actor after thirty seconds and the test clock advances by thirty seconds
- **THEN** the session actor receives Expire once

#### Scenario: Cancel before the send

- **WHEN** a scheduled send is cancelled before its delay ends
- **THEN** cancel reports that it stopped the timer, and the message never reaches the mailbox

#### Scenario: Cancel after the send

- **WHEN** a scheduled send is cancelled after the message was admitted
- **THEN** cancel reports that the timer had already fired, and the admitted message stays queued

#### Scenario: Scope exit

- **WHEN** a scope exits with a scheduled send that has not fired
- **THEN** the timer is cancelled and the message is never sent

### Requirement: Timer sends follow admission rules

A timer send SHALL use the admission rules of its destination. It SHALL wait while
a bounded mailbox is full, and it MUST NOT drop or overwrite a message. When the
destination is closed, the timer SHALL end without an error to the scope.

#### Scenario: Full mailbox

- **WHEN** a timer fires while its target's capacity-one mailbox is full
- **THEN** the message is admitted when space becomes free, and no message is lost

#### Scenario: Closed target

- **WHEN** a repeated send's target actor ends
- **THEN** the repeated send stops and the owner scope does not fail

### Requirement: Schedule values

A schedule SHALL be an immutable opaque value that gives a sequence of delays. It
SHALL support a fixed delay, a delay that doubles from a first value up to a
maximum, and a checked limit on the count of sends. Without a count limit, a
schedule SHALL repeat until it is cancelled. A test SHALL be able to list the
delays of a schedule without a runtime.

#### Scenario: Exponential schedule

- **WHEN** a test lists the delays of an exponential schedule from one second with a maximum of five seconds, limited to five sends
- **THEN** it gets one, two, four, five and five seconds

#### Scenario: No count limit

- **WHEN** a test takes the first 1,000 delays of a fixed one-second schedule with no count limit
- **THEN** it gets 1,000 delays of one second, and the schedule has more

#### Scenario: Schedule on all targets

- **WHEN** the portable schedule tests run on wasm, wasm-gc, js and native
- **THEN** they run and pass on each target

### Requirement: Repeated send with fixed delay

A scope SHALL send a message repeatedly to a destination on a schedule. Each delay
SHALL start after the previous message is admitted, so sends never pile up behind
backpressure. The repeated send SHALL stop at the end of its schedule, on cancel,
when its scope exits, or when the target closes.

#### Scenario: Count limit

- **WHEN** a repeated send uses a fixed one-second delay limited to three sends and the test clock advances by ten seconds
- **THEN** the target receives exactly three messages

#### Scenario: Backpressure delays the next send

- **WHEN** a repeated send waits two seconds for space in a full mailbox
- **THEN** the next delay starts after that admission, not from the original due time

### Requirement: Actor-owned keyed timers

An actor SHALL start single and repeated timers through its context, keyed by a
value of an application type with equality. Starting a timer with an existing key
SHALL cancel and replace the old timer. All timers of an actor SHALL stop when
the actor ends. A message that a cancelled or replaced actor timer has already
queued SHALL NOT reach any receive; the runtime removes it from the mailbox.

#### Scenario: Replace by key

- **WHEN** an actor starts a five-second timer with key Poll and then starts a two-second timer with key Poll, and the test clock advances by ten seconds
- **THEN** only the two-second timer fires

#### Scenario: Stale message after replacement

- **WHEN** a repeated timer with key Poll has queued Tick, and the actor starts a new Poll timer before it receives that Tick
- **THEN** the actor never receives the old Tick and receives the Tick messages of the new timer

#### Scenario: Stale message after cancel

- **WHEN** an actor cancels its Expire timer after the timer queued Shutdown but before the actor received it
- **THEN** the actor never receives that Shutdown, and other queued messages keep their order

#### Scenario: Scheduled sends keep admitted messages

- **WHEN** a scope cancels a send_after timer after its message was admitted
- **THEN** the message stays queued and the actor receives it, because only actor-owned keyed timers remove stale messages

#### Scenario: Actor end stops timers

- **WHEN** an actor with a pending timer ends
- **THEN** the timer never fires and the scope reports no error

#### Scenario: Typed keys

- **WHEN** a consumer starts a timer with a key whose type differs from the timer table's key type
- **THEN** the compiler rejects the consumer
