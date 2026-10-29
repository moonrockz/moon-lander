# Actors specification delta

## Purpose

Let applications run typed actors in memory with simple startup, private state,
mailbox delivery and explicit lifetime ownership.

## ADDED Requirements

### Requirement: Start an anonymous typed actor

An application SHALL start an actor from an initial state and one async message
handler inside an actor scope. It MUST NOT need an actor system, name, registry,
configuration file, builder chain, host or user-defined framework trait.

#### Scenario: Counter with default settings

- **WHEN** an application starts a counter with initial state zero and a handler for increment and read messages, sends increment and asks for the count
- **THEN** the reply is one, with no setup beyond the protocol, handler and scope

#### Scenario: Wrong message type

- **WHEN** a consumer sends a string to a reference whose protocol is a counter enum
- **THEN** the compiler rejects the consumer

### Requirement: Optional named discovery

An application SHALL optionally name message actors at startup and collect their
send references in immutable typed directories. Discovery SHALL preserve the
directory's protocol without dynamic casts or a caller-selected response
protocol. Anonymous actors SHALL remain available without directory setup.

#### Scenario: Discover a named actor

- **WHEN** a counter actor starts as counter, its reference is added to a counter directory, and another component looks up that name
- **THEN** it gets a counter reference that accepts increment messages without exposing actor state or lifecycle control

#### Scenario: Wrong discovery protocol

- **WHEN** a consumer uses the result of a counter-directory lookup as a reference for another protocol
- **THEN** the compiler rejects the consumer

### Requirement: Actor name rules

An actor name SHALL be a checked, immutable value of 1 through 128 ASCII
characters. It SHALL start with a letter and contain only letters, digits,
underscore, hyphen and dot thereafter. Names SHALL be case sensitive and SHALL
not be trimmed or normalized. Invalid names SHALL raise typed errors that retain
the input and the broken rule. Construction MUST NOT bypass the rules.

#### Scenario: Valid names and boundaries

- **WHEN** a caller parses a, worker-17, counter.total and a name of 128 ASCII letters
- **THEN** all names succeed and preserve their input spelling

#### Scenario: Invalid names

- **WHEN** a caller parses an empty name, 9counter, counter/total, a non-ASCII name, a name containing spaces or 129 ASCII letters
- **THEN** each parse fails with its input and a typed rule for the applicable length or character restriction

#### Scenario: Case-sensitive lookup

- **WHEN** Counter is registered in a directory and a caller looks up counter
- **THEN** the lookup gives no value unless counter has its own registration

### Requirement: Directory isolation

A directory SHALL contain only references supplied to its constructors and value
operations. Lookup MUST NOT search parent scopes or a process-global registry.
References from separate scopes SHALL be combinable when their protocols agree.
Directory membership MUST NOT confer actor ownership or lifecycle control.

#### Scenario: Same name in separate directories

- **WHEN** two scopes each start an actor as worker and each reference is put in a separate directory
- **THEN** each lookup finds only the actor explicitly included in its own directory

### Requirement: Actor lifetime addressing

Every actor SHALL have an opaque immutable local address for its lifetime.
Handles and send references SHALL expose that address. Copies SHALL preserve
identity. Separate actors, including replacements and actors in different scopes,
SHALL have distinct addresses. An address MUST NOT grant send or lifecycle
authority by itself. Address text SHALL be diagnostic rather than a resolvable URL.

#### Scenario: Anonymous actor identity

- **WHEN** an anonymous actor exposes an owner handle and several copied send references
- **THEN** all addresses compare equal without a user-supplied name

#### Scenario: Distinct scopes

- **WHEN** separate scopes start actors with identical names and local creation order
- **THEN** their addresses differ

### Requirement: Atomic name reservation

Named creation SHALL reserve its owner-scope name before user initialization runs.
A duplicate SHALL fail with a typed name-in-use error without running its
initializer, including when the message protocols differ. A reference SHALL be
returned only after successful startup.
Failed or cancelled startup SHALL release the reservation after its cleanup.

#### Scenario: Concurrent duplicate starts

- **WHEN** two creators concurrently start an actor under the same name in one owner scope
- **THEN** only one initializer runs and the other creator gets a typed name-in-use error

#### Scenario: Initialization still running

- **WHEN** an actor has reserved a name but its initializer has not completed
- **THEN** start has not returned a usable reference and another start under that name in the same scope fails name-in-use

#### Scenario: Failed initialization

- **WHEN** a named initializer fails or is cancelled after registering cleanup
- **THEN** no usable reference is returned, start reports the cause to its creator after cleanup, and a creator that catches the failure can reuse the name in the same live scope

### Requirement: Name reuse and stale references

Closing, draining or cancelling an actor SHALL keep its owner-scope name reserved
until processing and cleanup end. A later actor SHALL be able to reuse that name
with a fresh address. Old references MUST remain bound to the old actor and MUST
NOT redirect. Cleanup SHALL release only its own reservation. Existing directory
values SHALL retain their exact members until the caller creates a new value.

#### Scenario: Replacement with the same name

- **WHEN** actor A ends and actor B starts under the same owner-scope name
- **THEN** their addresses differ, an old directory still finds A, and a directory made by removing A and adding B finds B

#### Scenario: Closing actor still owns resources

- **WHEN** an actor closes while its async cleanup waits on a resource
- **THEN** another start under that name in the same scope fails name-in-use until cleanup ends, and existing directory membership does not change

### Requirement: Exact address resolution

A directory SHALL resolve an address only to that exact member, including a
closed member. An address absent from the value SHALL give no reference. Lookup
and resolve SHALL use structural membership without polling liveness. A directory
SHALL remain usable after its members' owner scopes exit. Sending to a closed
member SHALL follow the ordinary closed-actor rules.

#### Scenario: Resolve an old address after reuse

- **WHEN** actor B replaces actor A under the same name and a caller resolves A's address in an old directory
- **THEN** resolution returns A's closed reference and never B; a directory containing only B does not resolve A's address

#### Scenario: Close after lookup

- **WHEN** a caller gets a reference from lookup and its actor then closes before the send
- **THEN** send reports closed under the ordinary admission rules

#### Scenario: Escaped directory

- **WHEN** a saved directory is used after its members' owner scopes exit
- **THEN** lookup and resolve still identify its members and sends to those members report closed

### Requirement: Immutable directory values

A directory SHALL be an immutable finite set of typed send references keyed by
actor address. Empty and singleton constructors SHALL be available. Named and
anonymous references SHALL be valid members. Composition, addition, removal and
difference SHALL give new values without changing their inputs. Public mutable
collections MUST NOT expose directory membership.

#### Scenario: Preserve an earlier directory

- **WHEN** a caller adds B to a directory containing only A and removes A from the result
- **THEN** the original still contains only A, the intermediate contains A and B, and the final value contains only B

#### Scenario: Anonymous member

- **WHEN** an anonymous actor reference is added to an empty directory
- **THEN** its address resolves in the new directory even though it has no name

### Requirement: Directory union laws

Union SHALL be total, associative, commutative and idempotent under exact-address
membership equality. The empty directory SHALL be its identity. Duplicate copies
of the same actor reference SHALL produce one member. Enumeration order SHALL
not form part of equality. Combining different protocol types SHALL fail at
compile time.

#### Scenario: Composition laws

- **WHEN** directories A, B and C with overlapping member sets are combined
- **THEN** empty union A equals A, A union B equals B union A, both groupings of A union B union C agree, and A union A equals A

#### Scenario: Same reference through both inputs

- **WHEN** two directories contain copies of the same actor reference and are combined
- **THEN** the result has one member for that address and that repetition creates no name ambiguity

#### Scenario: Different protocol union

- **WHEN** a consumer combines a counter directory with a directory for an unrelated message protocol
- **THEN** the compiler rejects the combination

### Requirement: Directory reference removal

Adding a reference SHALL be union with its singleton directory. Removal SHALL
exclude only that exact actor address. Difference SHALL exclude all right-hand
addresses. Removing an absent member SHALL leave membership unchanged. Repeated
addition or removal of the same reference SHALL be idempotent.

#### Scenario: Remove an old lifetime

- **WHEN** a directory contains old and replacement actors with the same name and the old reference is removed
- **THEN** only the replacement remains under that name

#### Scenario: Repeated and absent removal

- **WHEN** a reference is removed twice, or a reference absent from the directory is removed
- **THEN** no error occurs and the second removal or absent removal changes no membership

#### Scenario: Directory difference

- **WHEN** A contains actors one and two, and B contains actors two and three
- **THEN** A minus B contains only one, A minus empty equals A, and A minus A is empty

### Requirement: Explicit directory name conflicts

Name lookup SHALL return missing, one found reference, or an explicit ambiguity
holding all distinct matching members. Union SHALL keep different actors that
share a name. It MUST NOT choose one through merge order or actor liveness. An
ambiguity value SHALL be immutable and valid only with at least two distinct
matching references.

#### Scenario: Same name from separate scopes

- **WHEN** two scopes each start worker and their singleton directories are combined in either order
- **THEN** worker lookup reports ambiguity with both addresses and exact resolution finds each member

#### Scenario: Remove a conflict member

- **WHEN** a two-member name conflict exists and one of those references is removed
- **THEN** name lookup finds the remaining reference without ambiguity

### Requirement: Directory operations preserve actor lifetimes

Directory operations SHALL change only discovery membership. They MUST NOT start,
stop, cancel, drain, rename or reparent actors. Holding a directory MUST NOT extend
an actor scope's lifetime. Removing a member MUST NOT revoke copies of its
reference or cancel work already admitted to its mailbox.

#### Scenario: Remove a live actor

- **WHEN** an actor is removed from a directory while another component holds its reference
- **THEN** the other reference can still send and admitted work can finish

#### Scenario: Removal preserves the name reservation

- **WHEN** a named live actor is removed from every directory and its owner scope attempts another start under the same name
- **THEN** the second start still fails name-in-use until the old actor and cleanup end

#### Scenario: Compose across owner scopes

- **WHEN** a directory combines actors from scopes A and B and scope A exits
- **THEN** A's actor stops, B's actor remains owned by B, and the directory retains both exact members

### Requirement: MoonBit directory operator forms

The API SHALL expose named union, add, remove and difference operations. Same-type
addition and subtraction SHALL be available for directories. Singleton conversion
SHALL permit a reference to take part in those operators. Documentation MUST use
syntax accepted by the pinned compiler and MUST NOT promise unsupported custom
or heterogeneous operator forms.

#### Scenario: Supported composition example

- **WHEN** a consumer combines two directories with addition, subtracts a singleton directory, and adds or removes references through methods
- **THEN** the example compiles on every supported runtime target and has the specified set semantics

### Requirement: Serialized private state

Each actor SHALL process messages on one consumer task with private state. A
handler MUST finish before the next handler starts, including across suspension.
The next state SHALL come from the previous handler's result. A reference MUST
NOT expose the state or receive operations.

#### Scenario: Concurrent producers

- **WHEN** two producers send increments while the first handler waits on an acknowledgement
- **THEN** the second handler starts after the first ends and a later read reports two

#### Scenario: Independent actors

- **WHEN** one actor waits for a message or async operation
- **THEN** a second actor can process its own messages

### Requirement: Receive-loop actors and results

An application SHALL start an actor from an async receive body. The body SHALL
have its typed inbox, self reference and a final result. Helpers SHALL support
processing until close, at most a checked positive count, and state transitions
that continue or stop. Only the actor body SHALL get the inbox. A receive while
another receive waits, or after the body ends, SHALL fail with a typed
ownership error.

#### Scenario: Finite actor

- **WHEN** a body receives three messages and returns their total
- **THEN** joining the actor returns the total and the actor accepts no more messages

#### Scenario: Second consumer

- **WHEN** another task receives from an inbox captured from an actor body while the body waits in receive, or after the body has ended
- **THEN** it gets a typed ownership error and removes no message

### Requirement: FIFO receive and polling

An ordinary receive SHALL take the oldest admitted message and wait when empty.
A receive with a time limit SHALL report a typed timeout when the limit expires.
A try receive SHALL return no value on timeout and poll once without a limit.
Both forms SHALL report a closed empty mailbox as closed, separately from timeout.

#### Scenario: Receive order

- **WHEN** messages A, B and C are admitted in that order
- **THEN** ordinary receives return A, B and C in that order

#### Scenario: Timeout preserves the mailbox

- **WHEN** a timed receive expires on an empty mailbox and a message is then admitted
- **THEN** the next receive returns that message

#### Scenario: Poll after close

- **WHEN** a caller polls a closed empty inbox
- **THEN** it gets a typed closed error rather than an empty-poll result

### Requirement: Selective receive

An actor SHALL select the oldest message for which a synchronous selector gives
a result. Unselected messages MUST remain queued in their relative order and
count toward capacity. A waiting scan SHALL inspect newly admitted messages.
Timed and try forms SHALL leave the mailbox unchanged on expiry or no match.

#### Scenario: Skip an earlier message

- **WHEN** the queue holds A, B and C, and a scan selects B
- **THEN** the scan returns its selected result and ordinary receives still return A then C

#### Scenario: Match after waiting

- **WHEN** a scan waits with only non-matching messages queued and a matching message is admitted
- **THEN** it selects the new message and retains the earlier non-matches

#### Scenario: Scan timeout

- **WHEN** a timed scan expires with only non-matching messages queued
- **THEN** a later ordinary receive still gets the oldest original message

### Requirement: Mailbox bounds and backpressure

The default mailbox SHALL hold at most 128 queued messages. A caller SHALL be
able to select a checked positive capacity or an unbounded mailbox. A full bounded
mailbox SHALL suspend send until admission is possible. No policy SHALL silently
drop or overwrite a message. The in-flight message SHALL not count as queued.

#### Scenario: Full mailbox

- **WHEN** a capacity-one mailbox has one queued message and a producer sends another
- **THEN** the producer waits until the consumer removes the queued message

#### Scenario: Non-matches still occupy capacity

- **WHEN** a capacity-one mailbox holds a non-match for a pending scan
- **THEN** another send waits and cancelling the scan does not remove the non-match

#### Scenario: Unbounded opt-in

- **WHEN** a caller explicitly selects an unbounded mailbox and admits more than 128 messages without receiving
- **THEN** no send waits for mailbox capacity

### Requirement: Admission outcomes and cancellation

Non-waiting send SHALL distinguish accepted, full and closed. Waiting send SHALL
return at admission, separately from processing. Cancellation before admission
SHALL leave no message. Cancellation after admission MUST NOT retract the message.
The runtime MUST NOT retry or deliver one admitted message more than once.

#### Scenario: Cancel a blocked producer

- **WHEN** a send waiting for capacity is cancelled before admission
- **THEN** the producer waiter is released and its message never appears in the mailbox

#### Scenario: Cancel after admission

- **WHEN** a sender is cancelled after its message is admitted
- **THEN** the actor can still process that message once

#### Scenario: Non-waiting send on full and closed

- **WHEN** a caller tries a non-waiting send first to a full mailbox and then after closure
- **THEN** it gets full and closed respectively, without suspension

### Requirement: Self messaging and queue observation

An actor SHALL obtain its own typed send reference. A non-waiting reenqueue SHALL
append to the same mailbox tail under its capacity rule. Queue length SHALL be
a snapshot of queued messages, including scan non-matches and excluding in-flight
work. The runtime SHALL yield between bounded batches of ready messages.

#### Scenario: Reenqueue keeps FIFO order

- **WHEN** B is queued and the actor re-enqueues C while processing A
- **THEN** the next ordinary receives return B then C

#### Scenario: Full self mailbox

- **WHEN** an actor re-enqueues a message into its full mailbox
- **THEN** it gets full without waiting or growing the mailbox

### Requirement: Typed one-shot request and reply

An ask SHALL build a protocol message with a fresh typed reply destination. The
first reply SHALL complete only its own request. Later replies SHALL return an
expired outcome without failing the actor. A protocol SHALL support different
reply types for different message cases without casts or dynamic lookup.

#### Scenario: Concurrent requests

- **WHEN** two callers ask one actor and it replies in reverse request order
- **THEN** each caller receives only its own reply

#### Scenario: Duplicate or late reply

- **WHEN** an actor replies twice to a request or replies after its caller times out
- **THEN** the duplicate or late reply reports expired and the actor can process another message

#### Scenario: Different replies in one protocol

- **WHEN** one protocol case replies with an integer and another replies with a string
- **THEN** both asks compile with their respective reply types and an incorrect reply type fails compilation

### Requirement: Ask deadline and termination

Ask SHALL use one deadline for admission and response, defaulting to 30 seconds.
A caller SHALL select another core time limit or explicitly wait until reply or
termination without a deadline. Try ask SHALL return no
value only on timeout. Target termination SHALL wake pending callers with closed
or a typed failure that retains its cause. Caller cancellation MUST NOT cancel
the actor or undo an admitted request.

#### Scenario: Admission consumes the deadline

- **WHEN** admission uses most of an ask's time limit and the reply exceeds the remaining time
- **THEN** ask times out within the original budget rather than starting a second budget

#### Scenario: Actor fails before replying

- **WHEN** an actor fails with a typed application error while callers wait for replies
- **THEN** all affected callers wake with actor failure holding that cause

#### Scenario: Cancel a caller

- **WHEN** an ask caller is cancelled after admission and the actor later handles the request
- **THEN** the request can change actor state and its reply reports expired

#### Scenario: Explicit indefinite wait

- **WHEN** a caller asks with an indefinite wait policy and the actor closes without replying
- **THEN** the ask wakes with closed even though no deadline was set

### Requirement: Automatic request responder

An application SHALL start a typed request actor with one async request handler
that returns its response. The framework SHALL send that response automatically.
A handler failure SHALL terminate the actor and wake pending callers. A domain
rejection represented in the reply type MUST NOT terminate the actor.

#### Scenario: No explicit reply plumbing

- **WHEN** an application starts a doubling handler and asks it for 21
- **THEN** it gets 42 without defining a message enum or sending an explicit reply

#### Scenario: Expected rejection

- **WHEN** a responder returns an error value in its result type for one request
- **THEN** that caller gets the error value and a subsequent valid request succeeds

### Requirement: Serialized service invocation

An application SHALL create a service actor and invoke its private service through
typed async closures. Ask SHALL return the closure's result or ordinary error to
its caller and continue processing. Tell SHALL wait only for admission; an
uncaught tell error SHALL fail the actor and its owner scope. Prior mutations
SHALL remain when a call raises.

#### Scenario: Heterogeneous return types

- **WHEN** a caller asks a service for an integer result and then a string result
- **THEN** both calls are typed without a message enum, cast or service registry

#### Scenario: Ask error permits later calls

- **WHEN** an ask closure changes service state and raises a typed error
- **THEN** its caller gets that error and the next call observes the changed state

#### Scenario: Tell failure reaches owner

- **WHEN** an admitted tell closure raises an unhandled error
- **THEN** the service ends, its cleanup runs and the owner scope fails

### Requirement: Typed message destinations

Actors, reply destinations, async queues and custom send functions SHALL adapt
to a common typed send-only destination. Message mapping SHALL adapt the input
type before admission without another queue or task. General destination asks
SHALL have the same deadline and one-shot reply rules as actor asks.

#### Scenario: Map an event to a protocol

- **WHEN** an event destination maps an event into an actor protocol case
- **THEN** the event enters the same mailbox as direct protocol messages

#### Scenario: Ask a custom destination

- **WHEN** a custom destination sends a response to the reply destination in the supplied request
- **THEN** the ask returns that typed response

### Requirement: Close and pending messages

Close SHALL reject new admission, wake blocked producers, return an immutable
snapshot of queued protocol messages once, and let the in-flight handler finish. Later
closes SHALL return no snapshot. Discarded requests SHALL fail promptly; an
in-flight request SHALL remain replyable until termination or its deadline.
Close SHALL return without waiting for the in-flight handler.

#### Scenario: Close with work in flight

- **WHEN** A is in flight, B and C are queued, and the actor is closed
- **THEN** close returns B and C in order, no new message is admitted, A can reply, and join waits for A and cleanup

#### Scenario: Repeated close

- **WHEN** two callers close the same actor
- **THEN** only one gets its pending-message snapshot and cleanup runs once

### Requirement: Service lifecycle operations

A service handle SHALL support close, drain, cancellation, status and join with
the same lifetime rules as message actors. Service close SHALL release queued
callers without exposing queued implementation closures or private service state.

#### Scenario: Close a service with queued calls

- **WHEN** a service is closed with one call running and another queued
- **THEN** the running call can finish, the queued caller wakes with closed, and no implementation closure or service state is returned

### Requirement: Drain and cancel

Drain SHALL reject new admission, process queued messages and wait for actor
completion. Cancelling a drain waiter MUST NOT reopen admission. Actor cancellation
SHALL discard queued work and request cooperative cancellation of in-flight work.
All affected pending callers SHALL be released. No hard preemption is promised.

#### Scenario: Drain processes admitted work

- **WHEN** an ordinary state actor is drained with A in flight and B queued
- **THEN** A and B finish, later sends fail closed and drain returns after cleanup

#### Scenario: Cancel during a wait

- **WHEN** an actor is cancelled while its handler waits for an async operation
- **THEN** the handler is cancelled, queued work does not run and pending asks wake

### Requirement: Structured actor ownership

Scope exit SHALL cancel live actors and join their cleanup before it returns.
Parent actor exit SHALL also cancel and join its children. Uncaught actor failure
SHALL fail the owner scope and cancel siblings. A body SHALL be able to catch
ordinary errors or use a nested scope as a failure boundary. No automatic restart
SHALL occur.

#### Scenario: Idle actor on normal scope exit

- **WHEN** a scope body returns while an actor waits forever on an empty inbox
- **THEN** the scope cancels that actor and returns after its cleanup rather than waiting for a message

#### Scenario: Parent completes normally

- **WHEN** a parent body returns a result while its child waits for messages
- **THEN** the child and its descendants are cancelled and cleaned up before the parent join completes

#### Scenario: Failure cancels siblings

- **WHEN** an actor raises an unhandled error while a sibling waits
- **THEN** the sibling is cancelled and the scope reports the error after cleanup

#### Scenario: Recovered body

- **WHEN** a body catches an ordinary handler error and continues receiving
- **THEN** the owner scope remains live and another message can be processed

#### Scenario: Escaped scope handle

- **WHEN** a caller uses a saved scope handle to start an actor after scope exit
- **THEN** it gets a typed closed-scope error rather than a runtime abort

### Requirement: Initialization and cleanup

An initializer SHALL finish before a usable actor handle is returned. Startup
failure SHALL expose its cause and leave no live actor. Registered cleanup SHALL
run once on normal exit, failure and cancellation. Async cleanup SHALL use
cancellation protection and a time limit, defaulting to five seconds. A cleanup
failure SHALL retain any primary failure and fail the owner scope.

#### Scenario: Initialization failure

- **WHEN** initialization raises after it has registered resource cleanup
- **THEN** start reports the cause, the resource is released once and no usable actor reference is returned

#### Scenario: Cleanup exceeds its budget

- **WHEN** async cleanup suspends beyond its supplied time limit
- **THEN** cleanup is cancelled and the scope reports a typed cleanup timeout with any primary failure

### Requirement: Observe actor termination

A handle SHALL provide a lifecycle snapshot and awaitable completion. Join SHALL
return the body result, rethrow its failure or report actor cancellation. Multiple
joiners SHALL observe the same terminal outcome. Cancelling one join waiter MUST
NOT cancel the actor or another waiter.

#### Scenario: Independent joiners

- **WHEN** two callers join an actor and one caller is cancelled before completion
- **THEN** the other caller still receives the actor's result

### Requirement: Scoped publish and subscribe

A typed topic SHALL deliver to a snapshot of subscribers in subscription order
through their destinations. Publish SHALL wait for admission, not processing.
Subscription SHALL end on unsubscribe or owner scope exit. Closed destinations
SHALL be pruned. Closing the topic SHALL reject later publish and subscribe.

#### Scenario: Fan-out to actors

- **WHEN** two actor destinations subscribe and one event is published
- **THEN** each actor gets one event in its own mailbox and publish need not wait for their handlers

#### Scenario: Scope removes subscriptions

- **WHEN** a subscriber's owner scope exits and a later publication takes its snapshot
- **THEN** that publication excludes the subscriber

#### Scenario: Subscriber backpressure and partial delivery

- **WHEN** publish admits to the first subscriber, waits for a full second subscriber and is cancelled
- **THEN** the first admission remains, the blocked admission is cancelled and later subscribers are not called

### Requirement: Checked actor policy values

Mailbox capacity and finite receive count SHALL be opaque positive values from
one through the largest Int. Their constructors SHALL reject invalid inputs with
typed errors that retain the input and rule. All time limits SHALL use the shared
core type. Public construction MUST NOT bypass these rules.

#### Scenario: Capacity and count boundaries

- **WHEN** a caller constructs capacity and count values with zero, negative one, one and the largest Int
- **THEN** zero and negative one fail with typed input errors, and one and the largest Int succeed

### Requirement: Supported runtime targets

Actor policy types SHALL build and test on wasm, wasm-gc, js and native. The async
runtime SHALL have the same public behavior on wasm, js and native, with explicit
event-loop requirements for wasm. The runtime MUST NOT claim wasm-gc support.
Examples SHALL compile as tests on every supported runtime target.

#### Scenario: Runtime acceptance matrix

- **WHEN** the actor acceptance gate runs
- **THEN** it runs nonzero actor tests on wasm, js and native, and portable policy tests on all four targets

#### Scenario: Unsupported runtime target

- **WHEN** a consumer imports the actor runtime on wasm-gc
- **THEN** the build rejects the unsupported package rather than supplying operations that abort at runtime
