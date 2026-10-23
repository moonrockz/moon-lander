# Spec Delta

## REMOVED Requirements

### Requirement: A publish handler error stops publish

**Reason**: The handlers of a topic are independent reactions to one event.
The owner chose the Foundatio.Mediator model, in which a failing handler
never prevents the other handlers from running.

**Migration**: A caller that catches the raw handler error from `publish`
catches `MediatorError::PublishFailed` instead and reads each failure from
it. A topic whose later handlers must not run after a failure checks for
that condition in the handlers, or uses one handler that calls the steps in
sequence.

## ADDED Requirements

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
