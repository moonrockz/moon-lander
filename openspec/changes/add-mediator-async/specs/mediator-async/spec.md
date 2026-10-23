# Spec Delta

## Purpose

The async mediator gives MoonBit applications message-based communication
with handlers that wait or do I/O: typed async senders, topics with
sequential or concurrent publish, cancellation, timeouts and one middleware
pipeline, with the same behavior on wasm, js and native.

## ADDED Requirements

### Requirement: Typed async sender registration

The system SHALL let an application build an async sender value from one
async handler that takes a context value and a request and gives a reply or
raises an error. The sender SHALL fix the context, request and reply types
at compile time. The system MUST NOT offer registration by text key or by
runtime type lookup.

#### Scenario: Send a ping through an async sender

- **WHEN** a caller sends `Ping("Hello")` through an async sender whose handler waits and then gives `"Pong: " + text`
- **THEN** the caller gets `"Pong: Hello"` and the handler runs one time

#### Scenario: A request of the wrong type

- **WHEN** an application sends a request of another type through an async sender
- **THEN** the program does not compile

### Requirement: Async send passes a handler error out unchanged

The system SHALL pass an error that the handler raises out of the async send
unchanged, unless a middleware handles it. The system MUST NOT turn a
handler error into a reply.

#### Scenario: Async handler raises

- **WHEN** an async handler raises an application error during a send
- **THEN** send raises the same error and gives no reply

### Requirement: Sequential publish runs every handler and reports every failure

The system SHALL let an application build an async topic from one async
handler and add more. A sequential publish SHALL call every handler one
time, one at a time, in add order, also after a handler fails, and SHALL then
raise one mediator error that lists each failure with its handler position,
in add order.

#### Scenario: Second of three async handlers raises

- **WHEN** the second of three async handlers raises an error during a sequential publish
- **THEN** each handler starts after the previous one ends, the three handlers run one time each, and publish raises one mediator error that lists the failure at position 2 of 3

#### Scenario: No async handler raises

- **WHEN** no handler raises an error during a sequential publish
- **THEN** every handler runs one time and publish finishes with no error

### Requirement: Concurrent publish runs every handler at the same time

The system SHALL offer a concurrent publish that starts every handler of the
topic, lets them run at the same time, and waits until all of them end. When
handlers fail, it SHALL raise one mediator error that lists each failure with
its handler position, in add order, whatever order the handlers end in.

#### Scenario: Handlers overlap

- **WHEN** a topic has two handlers that each wait before they end, and a caller publishes concurrently
- **THEN** the second handler starts before the first handler ends, and publish returns after both end

#### Scenario: Failures in add order

- **WHEN** during a concurrent publish the third handler fails first and the first handler fails later
- **THEN** publish raises one mediator error that lists the failure at position 1 before the failure at position 3

### Requirement: No publish returns before its handlers end

The system MUST NOT offer a publish that returns while a handler of that
publish still runs. A handler failure MUST NOT be lost while the publish
finishes normally.

#### Scenario: Return after the last handler

- **WHEN** a sequential or a concurrent publish returns normally
- **THEN** every handler of that publish has ended and no handler of that publish has failed

### Requirement: Caller cancellation stops the call and passes out unchanged

When the caller cancels a send or a publish, the system SHALL cancel the
running handlers, MUST NOT start the remaining handlers, and SHALL pass the
cancellation out as a cancellation. The system MUST NOT report a cancellation
as a failure in the combined publish error.

#### Scenario: Cancel a send

- **WHEN** the caller cancels a send while the handler waits
- **THEN** the handler stops, the caller gets no reply and no mediator error, and the call ends as cancelled

#### Scenario: Cancel a sequential publish

- **WHEN** the caller cancels a sequential publish while the second of three handlers waits
- **THEN** the second handler stops, the third handler does not start, and the publish ends as cancelled with no combined publish error

#### Scenario: Cancel a concurrent publish

- **WHEN** the caller cancels a concurrent publish while two handlers wait
- **THEN** both handlers stop and the publish ends as cancelled with no combined publish error

### Requirement: A timeout inside a handler is an ordinary failure

The system SHALL treat a timeout error that a handler raises from its own
time limit as an ordinary handler error: send passes it out unchanged, and a
publish lists it as a failure and runs the other handlers.

#### Scenario: One handler times out

- **WHEN** the first of two handlers raises a timeout error from its own time limit during a sequential publish
- **THEN** the second handler runs and publish raises one mediator error that lists the failure at position 1

### Requirement: The timeout middleware ends a slow call

The system SHALL offer a timeout middleware with a time limit in
milliseconds. When the next step does not end within the limit, the
middleware SHALL cancel the next step and raise a mediator timeout error that
holds the limit and no request values. A step that ends in time SHALL give
its reply unchanged.

#### Scenario: The handler is too slow

- **WHEN** a sender has a 50 ms timeout middleware and its handler waits 1000 ms
- **THEN** the handler stops before it ends, and send raises a mediator timeout error that holds 50 ms

#### Scenario: The handler ends in time

- **WHEN** a sender has a 1000 ms timeout middleware and its handler waits 10 ms
- **THEN** send gives the handler reply

### Requirement: Async middleware wraps send and publish

The system SHALL let an application attach async middleware to an async
sender or topic. A middleware SHALL get the context, the request or event,
and the next step, and MAY run code before and after the next step, change
the request or the reply, or give a reply without a call to the next step.
The first middleware attached SHALL be the outermost step.

#### Scenario: Two middleware on one async sender

- **WHEN** an application attaches middleware A and then middleware B to an async sender and sends a request
- **THEN** the run order is A, B, handler, B, A

#### Scenario: Middleware ends the call

- **WHEN** an async middleware gives a reply without a call to the next step
- **THEN** the handler does not run and the caller gets the middleware reply

### Requirement: The finally hook runs on every outcome

The system SHALL offer a finally middleware whose hook runs after the next
step when the step gives a reply, when it raises an error, and when the
caller cancels it. The hook MUST NOT hide the outcome of the next step.

#### Scenario: Finally after a cancellation

- **WHEN** a sender has a finally middleware and the caller cancels the send while the handler waits
- **THEN** the finally hook runs one time and the send ends as cancelled

### Requirement: The context value passes unchanged

The system SHALL give each async handler and middleware the exact context
value that the caller gives to send or publish, and MUST NOT hold it after
the call ends.

#### Scenario: Handler reads services from the context

- **WHEN** a caller sends with a context that holds a services record and the async handler reads a field of it after a wait
- **THEN** the handler reads the value from the record that the caller gave

### Requirement: Core senders and topics work as async ones

The system SHALL let an application wrap a core sender or topic, with its
middleware, as an async sender or topic. The wrapped value SHALL give the
same replies, errors and publish failures as the core value.

#### Scenario: Wrap a core sender

- **WHEN** an application wraps a core sender that has a log middleware and sends through the async value
- **THEN** the core middleware and handler run and the caller gets the core reply

### Requirement: Same async behavior on wasm, js and native

The system SHALL build and run the async mediator with the same public API
and the same behavior on the `wasm`, `js` and `native` targets. The package
MUST NOT contain per-target code. A test leg of the async mediator that runs
zero tests MUST NOT count as a pass.

#### Scenario: The acceptance suite on each target

- **WHEN** the async acceptance suite runs on `wasm`, `js` and `native`
- **THEN** each scenario gives the same result on each target and each target runs more than zero async mediator tests
