# actor-runtime-events Specification

## Purpose
Let applications and tests observe what the actors runtime does: actor starts,
actor ends and messages that are not delivered, through an explicit, typed and
non-waiting event channel for each scope, with optional Ion payloads.

## Requirements

### Requirement: Opt-in runtime event channel

A scope SHALL publish runtime events only when the caller gives it a runtime
event channel. A scope without a channel MUST NOT publish events and MUST NOT
encode payloads. The channel SHALL be an explicit value; there SHALL be no
process-global channel. One channel value MAY serve several scopes.

#### Scenario: Scope without a channel

- **WHEN** a scope has no runtime event channel and an actor with a JSON payload policy gets a message after it ends
- **THEN** no event is published and the payload encoder is not called

#### Scenario: One channel for two scopes

- **WHEN** two separate scopes get the same channel and each starts one actor
- **THEN** a subscriber of that channel gets a start event for each actor, with two different addresses

### Requirement: Child scopes use the parent channel

The child scope of an actor SHALL publish to the channel of its parent scope. A
separate top-level scope call SHALL use only the channel that its caller gives.

#### Scenario: Child actor events

- **WHEN** an actor in a scope with a channel starts a child actor
- **THEN** the channel gets the start and end events of the child

#### Scenario: Separate top-level scope

- **WHEN** an actor body calls a new top-level scope without a channel and starts an actor in it
- **THEN** the channel of the outer scope gets no event for that actor

### Requirement: Lifecycle events

The runtime SHALL publish a start event with the actor address when the actor
can receive messages, after initialization. It SHALL publish an end event when
processing and cleanup are complete, with the same end value that the actor
status reports. An actor whose initialization fails SHALL have neither event.

#### Scenario: Lifecycle order

- **WHEN** a subscriber watches a channel and an actor starts, processes one message and stops normally
- **THEN** the subscriber gets the start event and then one end event with the completed value

#### Scenario: Failed actor

- **WHEN** an actor handler raises an error
- **THEN** the end event holds the failed value with that error

#### Scenario: Failed initialization

- **WHEN** the initializer of an actor raises before the actor can receive
- **THEN** no start event and no end event is published for that actor

### Requirement: Undelivered message events

The runtime SHALL publish an undelivered event with the target address and a
reason when a mailbox that is full or closed does not admit a message, and when
stop, cancellation or failure discards a queued message. Messages that close
returns in its pending snapshot SHALL NOT produce undelivered events.

#### Scenario: Full mailbox

- **WHEN** a non-waiting send or reenqueue to a full mailbox is rejected
- **THEN** the channel gets an undelivered event with the full reason and the target address

#### Scenario: Closed mailbox

- **WHEN** a send or non-waiting send targets an actor that is closing or ended
- **THEN** the channel gets an undelivered event with the closed reason

#### Scenario: Discarded on cancellation

- **WHEN** an actor with two queued messages is cancelled
- **THEN** the channel gets two undelivered events with the discarded reason, in queue order

#### Scenario: Close returns pending messages

- **WHEN** an actor with two queued messages is closed
- **THEN** close returns both messages and the channel gets no undelivered event for them

### Requirement: Event order for one actor

For one actor, the start event SHALL come before all its other events, and its
discarded events SHALL come before its end event. After the end event, only
undelivered events with the closed reason SHALL follow.

#### Scenario: Discards before the end

- **WHEN** an actor with queued messages is cancelled
- **THEN** each discarded event comes after the start event and before the end event

#### Scenario: Send after the end

- **WHEN** a caller sends to an actor after its end event
- **THEN** the only later event for that actor is an undelivered event with the closed reason

### Requirement: Non-waiting event delivery

The runtime MUST NOT wait for an event subscriber and MUST NOT fail because of
one. When a subscriber cannot admit an event, the runtime SHALL drop that event
for that subscriber only and SHALL add one to that subscription's dropped count.
Other subscribers SHALL still get the event. The runtime MUST NOT publish an
event about the delivery of a runtime event. One subscriber SHALL get events in
the order that the runtime publishes them.

#### Scenario: Slow subscriber

- **WHEN** a subscriber with a capacity-one mailbox is full and the runtime publishes two events
- **THEN** the publishing actor does not wait, a second subscriber gets both events, and the dropped count of the first subscription is two

#### Scenario: No feedback events

- **WHEN** the runtime drops an event because a subscriber actor is full
- **THEN** no undelivered event is published for that drop

#### Scenario: Ended subscriber

- **WHEN** a subscriber actor ends while its subscription is active
- **THEN** later events skip it, and its end is not a failure of any other actor or scope

### Requirement: Runtime event subscriptions

A subscriber SHALL subscribe a typed destination to a channel through its own
scope. The subscription SHALL end on unsubscribe or when that scope exits.
Application code MUST NOT be able to publish an event to a runtime channel.
Closing the channel SHALL reject later subscriptions, end the current
subscriptions and stop all later publication to it.

#### Scenario: Subscription ends with its scope

- **WHEN** the scope of a subscriber exits and then an actor of another scope ends
- **THEN** the old subscriber destination gets no event

#### Scenario: Subscribe after close

- **WHEN** a caller subscribes to a closed channel
- **THEN** the subscription fails with a typed closed error

#### Scenario: No application publish

- **WHEN** application code tries to publish an event to a runtime channel
- **THEN** the code does not compile

### Requirement: Opt-in message payloads

An undelivered event SHALL hold a payload only when the actor's payload policy
selects one. The default policy SHALL omit the payload. The policy SHALL give
these forms: omit; Ion encoding for a protocol that can encode itself as Ion;
JSON encoding as a bridge for a protocol that can encode itself as JSON, which
holds that JSON as an Ion value; and a custom encoder to Ion. An encoder MUST
NOT be able to raise. Service closures SHALL never have a payload.

#### Scenario: Default omits payload

- **WHEN** an actor that has no payload policy gets a message after it ends
- **THEN** the undelivered event holds no payload

#### Scenario: Ion payload

- **WHEN** an actor uses the Ion policy and its protocol encodes a decimal and a timestamp
- **THEN** the payload holds an Ion decimal and an Ion timestamp with the same values

#### Scenario: JSON bridge payload

- **WHEN** an actor uses the JSON policy and its protocol derives JSON encoding
- **THEN** the payload is the Ion form of the JSON value of the message

#### Scenario: Redacted payload

- **WHEN** an actor uses a custom encoder that replaces a secret field with a fixed text
- **THEN** the payload holds the fixed text and not the secret

#### Scenario: Wrong payload policy

- **WHEN** a caller selects the Ion policy for a protocol with no Ion encoding
- **THEN** the code does not compile

### Requirement: Payload cost and isolation

The runtime SHALL call a payload encoder only for an undelivered event and only
when the channel has at least one active subscription. Each subscriber SHALL get
a payload value that is independent of the payload of other subscribers, so a
change by one subscriber is not visible to another.

#### Scenario: No subscriber

- **WHEN** a channel has no subscription and an actor with a counting custom encoder rejects ten messages
- **THEN** the encoder is called zero times

#### Scenario: Independent payloads

- **WHEN** two subscribers get the same undelivered event and the first changes a list in its payload
- **THEN** the payload of the second subscriber is unchanged

### Requirement: Runtime event targets

Runtime event behavior SHALL be the same on wasm, js and native. The payload
policy SHALL build and test on wasm, wasm-gc, js and native.

#### Scenario: Event acceptance matrix

- **WHEN** the actor acceptance gate runs
- **THEN** it runs nonzero runtime event tests on wasm, js and native, and payload policy tests on all four targets
