# Add object JSON properties

## Why

Morphir needs direct named property lookup in diagnostic JSON Lines. The ordered
array in schema version 1 retains duplicates but requires a local serializer.
Damian approved the exact object and duplicate-history contract in issue #112.

## What Changes

- Add an opt-in pure object formatter with schema version 2.
- Put named values under properties, with the last occurrence winning.
- Put all occurrences of each repeated name in duplicateProperties, in original
  per-name order, including the winner. Omit that object when no names repeat.
- Preserve JSON types and protect record metadata from event property names.
- Expose a typed FileSink policy and verify real rolling files on native and JS.
- Retain the existing formatter signature, schema version 1 and array default.

## Capabilities

### New Capabilities

- `object-json-properties`: opt-in named JSON properties and duplicate history.

### Modified Capabilities

- `logging-sinks`: permit the explicit schema version 2 policy while keeping the
  ordered schema version 1 default.

## Impact

The pure logging formatter and async file sink settings gain additive APIs.
Generated interfaces, runnable docs, formatter tests, public rolling acceptance
and registry consumer fixtures change. No dependency or I/O adapter changes.

## Out of scope

Root-level event fields, a caller-selected duplicate rule, changes to LogEvent's
first-value lookup API, profile discovery, actor implementation and publication
from a workstation. Publication uses the authorized shared-version release.
