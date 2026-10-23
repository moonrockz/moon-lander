# mediator Specification

## Purpose
Mediator gives MoonBit applications message-based communication inside one
process: typed request/response through sender values, publish to many
handlers through topic values, and one middleware pipeline for cross-cutting
steps, with the same behavior on every target.

## Requirements

### Requirement: Typed sender registration

The system SHALL let an application build a sender value from one handler
function. The handler takes a context value and a request and gives a reply
or raises an error. The sender fixes the context type, the request type, and
the reply type at compile time. The system MUST NOT offer registration by
text key or by runtime type lookup.

#### Scenario: Build a sender from a handler

- **WHEN** an application builds a sender from a handler that takes a `Ping` request and gives a `String` reply
- **THEN** the sender accepts only `Ping` requests and gives only `String` replies, and a request of another type does not compile

#### Scenario: No sender without a handler

- **WHEN** an application does not build a sender for a request type
- **THEN** no value exists that can send that request type, and the gap is a compile error, not a runtime error

### Requirement: Send gives the one handler reply

The system SHALL call the sender's one handler one time for each send, with
the context value and the request that the caller gives, and SHALL give the
handler's reply to the caller. A send MUST NOT call any other handler.

#### Scenario: Send a ping

- **WHEN** a caller sends `Ping("Hello")` through a sender whose handler gives `"Pong: " + text`
- **THEN** the caller gets `"Pong: Hello"` and the handler runs one time

#### Scenario: Two senders stay separate

- **WHEN** an application builds two senders from two handlers for two request types and sends through the first
- **THEN** only the first handler runs

### Requirement: Handler errors pass through send

The system SHALL pass an error that a handler raises out of send unchanged,
unless a middleware in the pipeline handles it. The system MUST NOT turn a
handler error into a reply value.

#### Scenario: Handler raises

- **WHEN** a handler raises an application error during a send
- **THEN** send raises the same error and gives no reply

### Requirement: Publish calls each handler in order

The system SHALL let an application build a topic value from one event
handler and add more handlers to it. Publish SHALL call each handler of the
topic one time, in the order the application added them, with the context
value and the event. A topic with no handlers is not a value the application
can build: a topic starts with one handler.

#### Scenario: Publish to three handlers

- **WHEN** an application adds two handlers to a topic that starts with one handler and publishes an event
- **THEN** the three handlers run one time each, in add order

#### Scenario: Publish does not give a reply

- **WHEN** a caller publishes an event
- **THEN** publish gives no reply value from any handler

### Requirement: Middleware wraps send and publish

The system SHALL let an application attach middleware to a sender or a
topic. A middleware gets the context value, the request or event, and the
next step. A middleware SHALL run code before and after it calls the next
step, MAY give a reply or finish without a call to the next step, and MAY
change the request before the next step or the reply after it. Middleware
MUST NOT change which handler a sender calls.

#### Scenario: Log middleware around a send

- **WHEN** a caller sends through a sender with a log middleware that records before and after the next step
- **THEN** the record shows the before entry, the handler runs, and the record shows the after entry

#### Scenario: Middleware ends the call

- **WHEN** a middleware gives a reply without a call to the next step
- **THEN** the handler does not run and the caller gets the middleware reply

#### Scenario: Middleware changes the reply

- **WHEN** a middleware takes the handler reply and gives a changed reply
- **THEN** the caller gets the changed reply

### Requirement: Middleware order is fixed

The system SHALL run middleware in the order the application attaches it:
the first middleware attached is the outermost step. The order MUST be the
same on every target and MUST NOT depend on registration time, hash order,
or runtime state.

#### Scenario: Two middleware on one sender

- **WHEN** an application attaches middleware A and then middleware B to a sender and sends a request
- **THEN** A runs before B on the way in, the handler runs, and B runs before A on the way out

### Requirement: The context value passes unchanged

The system SHALL give the handler and each middleware the exact context
value that the caller gives to send or publish. The core MUST NOT copy,
change, or hold the context value after the call ends.

#### Scenario: Handler reads the services from the context

- **WHEN** a caller sends with a context that holds a services record and the handler reads a field of that record
- **THEN** the handler reads the value from the record the caller gave

### Requirement: Same behavior on all targets

The system SHALL build and run with the same public API and the same
behavior on the `wasm`, `wasm-gc`, `js`, and `native` targets. The mediator
package MUST NOT contain per-target code, and a test leg for the mediator
that runs zero tests MUST NOT count as a pass.

#### Scenario: The ping example on each target

- **WHEN** the acceptance suite runs on `wasm`, `wasm-gc`, `js`, and `native`
- **THEN** the send, publish, and middleware scenarios give the same results on each target, and each target runs more than zero mediator tests

### Requirement: No runtime handler lookup

The system MUST NOT find a handler at runtime by name, by text key, by type
identity, or by scan of the application. Each send SHALL call the handler
that the sender value holds, as a direct function call.

#### Scenario: No registry in the public API

- **WHEN** a user reads the public interface of the mediator package
- **THEN** no function registers a handler under a text key and no function sends a request by text key or by untyped value

### Requirement: A publish runs every handler and reports every failure

The system SHALL call every handler of a topic one time, in add order, for
each publish, also after a handler raises an error. When one or more
handlers raise an error, the system SHALL raise one mediator error after the
last handler. That error SHALL hold the number of handlers and each failure,
with its handler position and the error that the handler raised, in add
order.

#### Scenario: Second of three handlers raises

- **WHEN** the second of three handlers raises an error during a publish
- **THEN** the three handlers run one time each, in add order, and publish raises one mediator error that lists one failure at position 2 of 3 handlers and holds the error that the second handler raised

#### Scenario: Two handlers raise

- **WHEN** the second and the third of three handlers raise an error during a publish
- **THEN** the three handlers run one time each, and publish raises one mediator error that lists the failures at positions 2 and 3, in that order, each with the error that its handler raised

#### Scenario: No handler raises

- **WHEN** no handler raises an error during a publish
- **THEN** every handler runs one time and publish finishes with no error

### Requirement: The publish failure text holds no event values

The system SHALL give a text for people for the combined publish error that
holds only the number of failures, the number of handlers, and the failed
handler positions. The text MUST NOT hold event values or the text of the
errors that the handlers raised.

#### Scenario: Event and handler error hold a secret

- **WHEN** a handler raises an error whose text holds a secret value, during a publish of an event that holds another secret value
- **THEN** the text of the combined publish error holds the failure count and the handler position, and holds neither secret value

### Requirement: Topic middleware gets the combined publish error

The system SHALL give a middleware that wraps a publish the one combined
publish error from its next step, not the separate handler errors. A
middleware that catches that error SHALL be able to finish the publish with
no error.

#### Scenario: Middleware catches the combined error

- **WHEN** a topic middleware calls the next step, the second of two handlers raises an error, and the middleware catches the error that the next step raises
- **THEN** the middleware gets one combined publish error that lists the failure at position 2, both handlers have run, and publish finishes with no error
