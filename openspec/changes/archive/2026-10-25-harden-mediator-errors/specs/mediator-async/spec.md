## MODIFIED Requirements

### Requirement: The timeout middleware ends a slow call

The system SHALL offer a timeout middleware with the shared core
`TimeLimit`. When the next step does not end within the limit, the
middleware SHALL cancel the next step and raise a mediator timeout error that
holds the same valid TimeLimit and no request values. A step that ends in time SHALL give
its reply unchanged.

#### Scenario: The handler is too slow

- **WHEN** a sender has a 50 ms timeout middleware and its handler waits 1000 ms
- **THEN** the handler stops before it ends, and send raises a mediator timeout error that holds 50 ms

#### Scenario: The handler ends in time

- **WHEN** a sender has a 1000 ms timeout middleware and its handler waits 10 ms
- **THEN** send gives the handler reply

## ADDED Requirements

### Requirement: Core wrapping uses a typed alternative

An async topic SHALL represent a wrapped core topic separately from its own
async handlers. The core alternative MUST NOT permit extra handlers that publish
would ignore. Attaching middleware SHALL keep that alternative. Adding a handler
SHALL give ordinary async handlers, with the core publish at position 1.

#### Scenario: Middleware on a wrapped core topic

- **WHEN** a caller attaches async middleware to a wrapped core topic and publishes sequentially or concurrently
- **THEN** the middleware runs and the original core publish error passes out unchanged

#### Scenario: Add after wrapping

- **WHEN** a caller adds an async handler to a wrapped core topic and publishes sequentially or concurrently
- **THEN** both handlers run, and any core publish error is the nested failure at position 1 of the combined error
