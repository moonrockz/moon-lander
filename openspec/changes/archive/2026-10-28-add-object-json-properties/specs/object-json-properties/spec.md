# Object JSON properties delta

## Purpose

Provide named diagnostic values and complete duplicate history through an opt-in
JSON Lines formatter and public rolling file sink, while keeping the array default.

## ADDED Requirements

### Requirement: Opt-in object format

The pure formatter SHALL expose an opt-in JSON Lines object format with schema
version 2. Each record SHALL contain a properties object. Event property names
MUST remain inside that object and MUST NOT replace record metadata. The current
formatter signature, schema version 1 ordered array output and sink default SHALL
remain compatible.

#### Scenario: Direct lookup without metadata collision

- **WHEN** an event has path and level properties and the object format is selected
- **THEN** the values are available at properties.path and properties.level, and the record level retains its metadata value

#### Scenario: Existing default

- **WHEN** an existing caller uses format_json_line or a JsonLines FileSink without a property policy
- **THEN** properties remains an ordered array and schemaVersion remains 1

### Requirement: Last value and complete duplicate history

The LAST occurrence in the event's ordered property list SHALL win in
properties[name]. For every repeated name, duplicateProperties[name] SHALL contain
ALL occurrences in original per-name order, INCLUDING the winner. Names occurring
once SHALL be absent from duplicateProperties. When no names repeat, the record
SHALL omit duplicateProperties entirely.

#### Scenario: Interleaved repeated names

- **WHEN** path occurs three times and command twice, with unrelated properties between occurrences
- **THEN** properties holds the last value of each name and duplicateProperties holds all path and command values in their respective original orders

#### Scenario: No repeated names

- **WHEN** an event has zero properties or each name occurs once
- **THEN** properties is an object and duplicateProperties is absent

### Requirement: Preserve JSON values

The object format SHALL preserve each value's JSON type, including null, arrays
and nested objects. One array-valued property MUST remain distinct from duplicate
history. Strings and names SHALL use JSON escapes and records SHALL remain one
physical line with a final LF. Existing handling of non-finite numbers SHALL remain.

#### Scenario: Mixed duplicate values

- **WHEN** one name occurs with null, an array and an object
- **THEN** the object is the winner and history contains null, the array and the object without flattening or conversion to text

#### Scenario: One array-valued property

- **WHEN** a name occurs once with an array value
- **THEN** its value remains an array and it does not cause duplicateProperties to appear

### Requirement: Public rolling sink selection

FileSink SHALL expose a typed opt-in named property policy for JsonLines. The
selected formatter SHALL apply to every record across rolling, draining and
restart. The policy SHALL not change Text rendering, file naming, ownership or
retention. Tests SHALL decode actual public rolling sink files with an independent
JSON parser on native and JS and verify default compatibility.

#### Scenario: Object records across file rolls

- **WHEN** a public session selects object properties, writes mixed events and rolls its file
- **THEN** each decoded file record follows the approved winner, history, type and metadata rules and close drains all accepted records
