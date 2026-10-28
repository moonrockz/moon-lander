# Logging sinks delta

## MODIFIED Requirements

### Requirement: Readable and JSON Lines file formats

File sinks SHALL support UTF-8 text and JSON Lines without a BOM or color.
JSON Lines MUST write one object and LF per event, preserving captured time,
level, category, template, message, property values and error text. Schema
version 1 SHALL remain the default and keep all properties in order as an array.
Opt-in version 2 SHALL use named last-wins values and complete per-name history
as defined in object-json-properties.

#### Scenario: Structured values survive JSON output

- **WHEN** a record contains a number, nested object, repeated property name, and newline in error text and uses the default JSON policy
- **THEN** decoding its single JSON line recovers every property in order, including duplicate names, with its original JSON type

#### Scenario: Named JSON output

- **WHEN** a JsonLines sink selects NamedObject
- **THEN** its records use schema version 2 with named last-wins properties and complete duplicate history, without changing captured metadata

#### Scenario: Human-readable file output

- **WHEN** a text file receives a record with category and error
- **THEN** it contains a UTC timestamp, level code, category and message, followed by indented error text without color sequences
