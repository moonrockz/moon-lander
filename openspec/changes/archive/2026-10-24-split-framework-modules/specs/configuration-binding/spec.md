# Spec Delta

## ADDED Requirements

### Requirement: Bind a time limit

The system SHALL bind a time limit from a configuration text value with the
time-limit text form. A value that is not text, or text that does not parse, MUST
fail with a decode error for the key. The error MUST name the time-limit rule that
the text breaks, and MUST blame the sources that set the key.

#### Scenario: Bind a timeout

- **WHEN** a TOML source sets `http.timeout = "1m 30s"`
- **AND** an application binds `http.timeout` to a time limit
- **THEN** the bound limit has 90 000 milliseconds

#### Scenario: Integer value

- **WHEN** a TOML source sets `http.timeout = 5000`
- **AND** an application binds `http.timeout` to a time limit
- **THEN** binding fails with a decode error for `http.timeout` that says a time limit is text with a unit

#### Scenario: Bad text

- **WHEN** a TOML source in `/w/app.toml` sets `http.timeout = "30d"`
- **AND** an application binds `http.timeout` to a time limit
- **THEN** binding fails with a decode error for `http.timeout` that names the rule "unknown unit" and blames `/w/app.toml`

#### Scenario: Optional time limit

- **WHEN** no source sets `http.timeout`
- **AND** an application binds `http.timeout` to an optional time limit
- **THEN** the bound value is `None`
