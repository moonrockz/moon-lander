## ADDED Requirements

### Requirement: Mediator errors are valid by construction

The system SHALL permit external callers to match mediator errors and SHALL
prevent direct construction of their cases. It SHALL supply a supported
rejection constructor and a timeout constructor that accepts the core
`TimeLimit`. A timeout error SHALL hold that valid limit.

#### Scenario: Construct a rejection or a timeout

- **WHEN** a caller uses the rejection constructor or gives a valid TimeLimit to the timeout constructor
- **THEN** the error holds the given reason or limit and its message holds no request values

#### Scenario: Derive a publish error

- **WHEN** an adapter gives one optional error per handler in add order to the derived publish constructor
- **THEN** no failures gives no error, and failed slots give a publish error with a positive handler count and one read-only failure per failed slot, with positions from 1 through the handler count in add order

### Requirement: Publish failure reports cannot change

The system SHALL prevent external construction of publish failures and SHALL
protect the failure collection from mutation. It SHALL provide a count, optional
indexed access and an array copy. Changing an input outcome array or an output
failure array MUST NOT change an existing error.

#### Scenario: A caller changes arrays

- **WHEN** a caller changes the outcome array after construction or clears an array copy from the failure collection
- **THEN** the error keeps the same failures, handler positions, handler count and message

#### Scenario: An index is outside the report

- **WHEN** a caller asks for a failure at a negative index or at the collection length
- **THEN** optional access gives None
