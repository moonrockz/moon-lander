# Spec Delta

## Purpose

Time limits give the framework one checked type for a positive, bounded amount of
time, such as a request timeout or a shutdown timeout, with constructors for code and
a text form for configuration.

## ADDED Requirements

### Requirement: Time limit range

A time limit SHALL be a whole number of milliseconds from 1 to 2 147 483 647, the
largest `Int`. No constructor MUST give a value out of this range. A value MUST NOT
change after construction.

#### Scenario: Smallest limit

- **WHEN** code makes a time limit of 1 millisecond
- **THEN** it succeeds and its millisecond count is 1

#### Scenario: Zero

- **WHEN** code makes a time limit of 0 milliseconds
- **THEN** it fails with a time-limit error for the rule "greater than zero" that holds the input

#### Scenario: Negative

- **WHEN** code makes a time limit of -1 milliseconds
- **THEN** it fails with a time-limit error for the rule "greater than zero" that holds the input

#### Scenario: Largest limit

- **WHEN** code makes a time limit of 2 147 483 647 milliseconds
- **THEN** it succeeds

#### Scenario: Above the largest limit

- **WHEN** code makes a time limit of 2 147 483 seconds, which is 2 147 483 000 milliseconds, and then 2 147 484 seconds
- **THEN** the first succeeds and the second fails with a time-limit error for the rule "not more than the largest limit"

### Requirement: Time limit constructors

The system SHALL make a time limit from a count of milliseconds and from a count of
seconds. It SHALL give the count of milliseconds back as an `Int` with no failure, so
that a caller can pass it to `moonbitlang/async`.

#### Scenario: From seconds

- **WHEN** code makes a time limit of 30 seconds
- **THEN** its millisecond count is 30 000

#### Scenario: Equal values

- **WHEN** code makes one time limit of 1 500 milliseconds and parses another from `1.5s`
- **THEN** the two limits are equal, and each compares less than a limit of 2 seconds

### Requirement: Time limit text form

The system SHALL parse a time limit from one or more parts. Each part is a decimal
number, an optional space and a unit. Parts MUST go from the largest unit to the
smallest, with each unit at most one time, and with an optional space between parts.
The total MUST be in the time-limit range.

#### Scenario: Short units

- **WHEN** the system parses `9ms`, `9 ms`, `10s`, `5m` and `2h`
- **THEN** the millisecond counts are 9, 9, 10 000, 300 000 and 7 200 000

#### Scenario: Long units

- **WHEN** the system parses `1 millisecond`, `10 seconds`, `1 second`, `2 minutes` and `1 hour`
- **THEN** the millisecond counts are 1, 10 000, 1 000, 120 000 and 3 600 000

#### Scenario: Compound value

- **WHEN** the system parses `2m30s`, `1h 15m` and `1h 2m 3s 4ms`
- **THEN** the millisecond counts are 150 000, 4 500 000 and 3 723 004

#### Scenario: Decimal number

- **WHEN** the system parses `1.5s` and `0.25 hours`
- **THEN** the millisecond counts are 1 500 and 900 000

### Requirement: Time limit text errors

A parse failure SHALL raise a time-limit error that holds the input text and names
the broken rule as an enum case. Each rule in the scenarios MUST have its own case.

#### Scenario: Number without a unit

- **WHEN** the system parses `5000`
- **THEN** it fails with the rule "missing unit"

#### Scenario: Unknown unit

- **WHEN** the system parses `30d`, `10 secs` and `10 Seconds`
- **THEN** each fails with the rule "unknown unit" and the unit text `d`, `secs` or `Seconds`

#### Scenario: Less than one millisecond

- **WHEN** the system parses `1ms` and `0.5ms`
- **THEN** the first succeeds and the second fails with the rule "not a whole number of milliseconds"

#### Scenario: Fraction of a millisecond in seconds

- **WHEN** the system parses `1.001s` and `1.0005s`
- **THEN** the first succeeds with 1 001 milliseconds and the second fails with the rule "not a whole number of milliseconds"

#### Scenario: Zero total

- **WHEN** the system parses `0s`
- **THEN** it fails with the rule "greater than zero"

#### Scenario: Sign

- **WHEN** the system parses `-1s` and `+1s`
- **THEN** each fails with the rule "not a number"

#### Scenario: Above the largest limit

- **WHEN** the system parses `596h` and `597h`
- **THEN** the first succeeds and the second fails with the rule "not more than the largest limit"

#### Scenario: Parts out of order

- **WHEN** the system parses `30s 1m`
- **THEN** it fails with the rule "units out of order"

#### Scenario: Repeated unit

- **WHEN** the system parses `1m 1m`
- **THEN** it fails with the rule "repeated unit"

#### Scenario: Empty or extra space

- **WHEN** the system parses the empty text, ` 10s`, `10s `, `10  s` and `1m  30s`
- **THEN** each fails with the rule "unexpected space" or, for the empty text, the rule "empty"

### Requirement: Time limit text round trip

The text form of a time limit SHALL be its compound form with short units and no
spaces, from hours to milliseconds, with each zero part left out. Parsing that text
MUST give an equal limit.

#### Scenario: Canonical text

- **WHEN** code shows time limits of 150 000, 1 500 and 3 723 004 milliseconds
- **THEN** the texts are `2m30s`, `1s500ms` and `1h2m3s4ms`

#### Scenario: Round trip

- **WHEN** the system parses the text form of any valid time limit
- **THEN** it gives a limit equal to the first
