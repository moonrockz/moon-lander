## ADDED Requirements

### Requirement: Immutable message segments for formatters

An event SHALL expose its rendered message as ordered literal and bound-value
segments. Concatenating the segment text MUST give the existing `message()`
result. Bound segments MUST retain the property's JSON type. Reads MUST give
copies of mutable values. Existing template mismatch and repeated-name rules
MUST remain unchanged.

#### Scenario: Renderers distinguish text and values

- **WHEN** an event has template `Loaded {Count} files from {Path}` and arguments `3` and `src`
- **THEN** a renderer can distinguish both bound values from the literal text and recover the message `Loaded 3 files from src`

#### Scenario: Existing template behavior is preserved

- **WHEN** events contain escaped braces, missing arguments, malformed holes, or repeated property names
- **THEN** concatenated segment text equals the existing message text in every case

#### Scenario: A renderer cannot mutate a kept event

- **WHEN** a reader changes an array or object obtained from a bound segment
- **THEN** later segment, property, and message reads return the original values
