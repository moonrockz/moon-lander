# Spec Delta: configuration-binding

## Purpose

Configuration binding reads a section of the merged configuration as a typed
application value. Each failure names the decode path and the sources that set the
bad value, so that a user can find and correct it.

## ADDED Requirements

### Requirement: Bind a section to a typed value
The system SHALL decode the configuration section at a given key path into a value
of any type that implements the MoonBit `FromJson` trait. The key path SHALL be
non-empty and SHALL NOT hold a list index. Key text that is empty or does not parse
SHALL raise the core key path error. Binding SHALL NOT change the configuration.

#### Scenario: Section decodes into a record
- **WHEN** the merged configuration has `ir.layout = "single-file"` and `ir.strict_mode = true`
- **AND** the application binds key `ir` to a record with the fields `layout` and `strict_mode`
- **THEN** the result has `layout` equal to `"single-file"` and `strict_mode` equal to `true`

#### Scenario: Empty key text is rejected
- **WHEN** the application binds the empty key text
- **THEN** binding fails with the core key path error

#### Scenario: Map type receives each child key
- **WHEN** the section `backends` has the children `ts` and `scala`
- **AND** the application binds `backends` to a map from text to a record
- **THEN** the map has the keys `ts` and `scala`, each with its decoded record

### Requirement: Bind the full configuration
The system SHALL supply a separate root binding operation that decodes the full
merged configuration into a value of any type that implements `FromJson`. Decode
errors from the root binding SHALL use the same decode paths and origins as section
binding.

#### Scenario: Root binding fills each top-level table
- **WHEN** the merged configuration has the tables `ir` and `pipeline`
- **AND** the application calls the root binding with a record that has the fields `ir` and `pipeline`
- **THEN** each field holds the decoded value of its table

#### Scenario: Root binding error names the full path
- **WHEN** a source sets `ir.strict_mode = "yes"`
- **AND** the application calls the root binding with a record whose `ir.strict_mode` field is a boolean
- **THEN** binding fails with a decode error whose path text is `ir.strict_mode`

### Requirement: Absent section
When no source sets the given key path, the system SHALL decode the section as an
absent value. An optional target type SHALL get no value. Any other target type
SHALL fail with a decode error that says no source sets the key.

#### Scenario: Optional target with no section
- **WHEN** no source sets `telemetry`
- **AND** the application binds `telemetry` to an optional record
- **THEN** the result is no value and no error occurs

#### Scenario: Required target with no section
- **WHEN** no source sets `ir`
- **AND** the application binds `ir` to a record without a default
- **THEN** binding fails with a decode error for key path `ir`
- **AND** the error says that no source sets the key

### Requirement: Bind over a default value
The system SHALL bind a section over a typed default value. It SHALL convert the
default to a value tree, merge the configuration section over it with the same
merge rules as the configuration core, and decode the result. The default value
SHALL NOT change.

#### Scenario: Unset keys keep default values
- **WHEN** the default has `layout = "single-file"` and `strict_mode = false`
- **AND** the configuration sets only `ir.strict_mode = true`
- **THEN** the result has `layout = "single-file"` and `strict_mode = true`

#### Scenario: Scalar default

- **WHEN** the default for `mode` is the text `safe`
- **AND** the configuration does not set `mode`
- **THEN** binding gives `safe`, and with `mode = "fast"` set it gives `fast`

#### Scenario: Configured list replaces default list
- **WHEN** the default has `components = ["parse", "typecheck"]`
- **AND** the configuration sets `pipeline.components = ["parse"]`
- **THEN** the bound value has `components = ["parse"]`

#### Scenario: No section uses the full default
- **WHEN** no source sets `ir`
- **AND** the application binds `ir` over a default
- **THEN** the result equals the default

### Requirement: Decode errors name the decode path and its sources
When decoding fails, the system SHALL raise the decode case of the core
configuration error. The error SHALL hold a decode path, the decoder detail, and
the origins of the sources that set the failing value. The decode path SHALL hold
the key path of the failing value and, inside a list, a suffix of list indexes and
field names. The text form SHALL show a list index as `[n]`. Binding SHALL NOT
define an error type of its own.

#### Scenario: Wrong type in a file
- **WHEN** `/repo/morphir.toml` sets `ir.strict_mode = "yes"`
- **AND** the application binds `ir` to a record whose `strict_mode` field is a boolean
- **THEN** binding fails with a decode error for key path `ir.strict_mode`
- **AND** the error origin names the file `/repo/morphir.toml`

#### Scenario: Failure inside a list
- **WHEN** the section `targets` is a list and its second element has a field `level` of the wrong type
- **THEN** the error path text is `targets[1].level`
- **AND** the error origins are the origins of the list `targets`

#### Scenario: Appended list names every source
- **WHEN** two sources append to the list `targets` and an element of `targets` fails to decode
- **THEN** the error names both sources, in merge order
- **AND** the list of origins in the error is not empty

#### Scenario: Value from an environment variable
- **WHEN** the environment variable `MORPHIR_IR__STRICT_MODE` sets `ir.strict_mode` to the text `maybe`
- **AND** the target field is a boolean
- **THEN** the error origin names the environment source and that variable

### Requirement: Decode errors for tables, unset and default values
When the failing key is a table, the system SHALL report the sources that set keys
in that table. When the failing key has no value, the system SHALL report that no
source sets it. When the failing value came from a bind default, the system SHALL
report the default, not a configuration source.

#### Scenario: Required field with no value
- **WHEN** `/repo/morphir.toml` sets `ir.strict_mode` but no source sets `ir.layout`
- **AND** the target record requires `layout` and has no default
- **THEN** the error names the key path `ir` and its detail names the missing field `layout`
- **AND** the error lists `/repo/morphir.toml` as a source of the table `ir`

#### Scenario: Unset scalar key
- **WHEN** no source sets `server.port`
- **AND** the application binds `server.port` to an integer
- **THEN** the error names `server.port` and says that no source sets it

#### Scenario: Bad default value
- **WHEN** a default value converts to a tree that the target type cannot decode
- **AND** no source sets the failing key
- **THEN** the error says that the value came from the bind default

### Requirement: Origin text in errors
Error text SHALL show each origin as the core gives it: for a file source, the file
role name and the file path; for the environment source, the variable name. File
paths SHALL use `/` as the separator on every platform, Windows included.

#### Scenario: File role name in the error
- **WHEN** the user override file `/repo/morphir.user.toml` sets `ir.strict_mode = "yes"`
- **AND** the target field is a boolean
- **THEN** the error text names the file role `user-override` and the path `/repo/morphir.user.toml`

#### Scenario: Windows path uses forward slashes
- **WHEN** on Windows the file `C:/repo/morphir.toml` sets `ir.strict_mode = "yes"`
- **AND** the target field is a boolean
- **THEN** the error text shows the path `C:/repo/morphir.toml`
- **AND** the error text contains no backslash

### Requirement: Error text does not show configured values
Text that the binding system generates for decode and validation errors SHALL NOT
include the configured value. It SHALL include only decode paths, origins, type
expectations and the detail text that the application supplies.

#### Scenario: Wrong type for a secret-like key
- **WHEN** the configuration sets `service.api_token = 42` and the target field is text
- **THEN** the error text names `service.api_token` and its origin
- **AND** the error text does not contain `42`

### Requirement: Secret references are not resolved by binding
Binding SHALL NOT resolve a secret reference. A secret reference SHALL decode only
into the secret reference type through exact decoding. Any other target SHALL fail
with a decode error that names the decode path and origin and says the value is a
secret reference.

#### Scenario: Secret reference into a text field
- **WHEN** the configuration sets `service.token = { env = "SERVICE_TOKEN" }`
- **AND** the target field `token` is text and decodes through `FromJson`
- **THEN** binding fails with a decode error for `service.token` that says the value is a secret reference
- **AND** the system does not read `SERVICE_TOKEN`

#### Scenario: Secret reference into the reference type
- **WHEN** the target field `token` has the secret reference type and decodes through exact decoding
- **THEN** the result holds the unresolved reference
- **AND** the system does not read `SERVICE_TOKEN`

### Requirement: Optional unknown-key check
For a target type that implements both `ToJson` and `FromJson`, the system SHALL
offer a check that finds configured keys that the decoded value does not contain.
The check SHALL be off by default. When on, each unknown key SHALL be reported
with its key path and origin. The check SHALL also accept the relative key paths
that the application lists, for decoders that accept keys their encoder does not
write.

#### Scenario: Unknown key ignored by default
- **WHEN** the configuration sets `ir.strict_mod = true` (a misspelled key)
- **AND** the application binds `ir` with the check off
- **THEN** binding succeeds and ignores `ir.strict_mod`

#### Scenario: Accepted alias listed

- **WHEN** a type with a hand-written decoder accepts `port` and its encoder writes `endpoint`
- **AND** the configuration sets `server.port` and the application binds `server` over a default with `RejectExcept(["port"])`
- **THEN** binding succeeds and reports no unknown key

#### Scenario: Unknown key rejected
- **WHEN** the configuration file `/repo/morphir.toml` sets `ir.strict_mod = true`
- **AND** the application binds `ir` over a default with the unknown-key check on
- **THEN** binding fails with an error that names `ir.strict_mod` and `/repo/morphir.toml`

### Requirement: Validation reports all failures with sources
The system SHALL let a type declare validation rules that run after decoding.
Validation SHALL report all failures together in the validation case of the core
configuration error. Each failure SHALL name one or more decode paths, each with
the origins of its value, and a detail text.

#### Scenario: Two failures in one section
- **WHEN** a bound `pipeline` value has an empty `target` and an unknown `validation` mode
- **THEN** validation fails with one error that holds two failures
- **AND** each failure names its decode path and the source that set the value

#### Scenario: Cross-field failure
- **WHEN** a rule needs `strict_mode = true` if `layout = "split"`, and both values break the rule
- **THEN** the failure names both `ir.layout` and `ir.strict_mode`, each with its origin

#### Scenario: Type without rules
- **WHEN** a type declares no validation rules
- **THEN** validation of any value of that type succeeds

### Requirement: Options value
The system SHALL supply an immutable options value that holds a bound and
validated value, the key path it came from, and an optional instance name. The
system SHALL create an options value only after decoding and validation succeed.

#### Scenario: Options from a valid section
- **WHEN** the application binds and validates `ir` and both steps succeed
- **THEN** the options value holds the decoded value and the key path `ir`

#### Scenario: No options value after a validation failure
- **WHEN** validation of `ir` fails
- **THEN** the application gets the validation error and no options value

### Requirement: Named options
The system SHALL bind each child of a section as one named instance of the same
type. It SHALL report the decode and validation failures of all instances
together. An absent section SHALL give an empty set of named options.

#### Scenario: Each child is a named instance
- **WHEN** the section `backends` has the children `ts` and `scala`
- **THEN** the named options have the instances `ts` and `scala`
- **AND** the instance `ts` has the name `ts` and the key path `backends.ts`

#### Scenario: Failures in two instances
- **WHEN** the instance `ts` fails to decode and the instance `scala` fails validation
- **THEN** one error holds both failures, each with its decode path and origin

### Requirement: Exact decoding from the value tree
The system SHALL let a type decode directly from the configuration value tree.
Exact decoding SHALL keep Ion decimals, timestamps and integers of any size
exactly. It SHALL give the same decode path and origin in errors as JSON decoding.

#### Scenario: Decimal keeps its scale
- **WHEN** an Ion source sets `billing.rate = 1.50d0`
- **AND** the target field is an Ion decimal and decodes exactly
- **THEN** the bound decimal has the coefficient `150` and the exponent `-2`

#### Scenario: Timestamp keeps precision and offset
- **WHEN** an Ion source sets `release.at = 2026-10-19T08:30:00.125+02:00`
- **AND** the target field is an Ion timestamp
- **THEN** the bound timestamp has millisecond precision and the offset `+02:00`

#### Scenario: Large integer into Int64
- **WHEN** a source sets `limits.max = 9007199254740993`
- **AND** the target field is `Int64` and decodes exactly
- **THEN** the bound value is `9007199254740993`

#### Scenario: Fraction into Int fails
- **WHEN** a source sets `server.port = 80.5`
- **AND** the target field is `Int` and decodes exactly
- **THEN** binding fails with a decode error for `server.port`

### Requirement: Value with its origin
The system SHALL let a field hold a decoded value together with the origin of that
value, so that the application can resolve a relative path against the file that
set it.

#### Scenario: Relative path with its file
- **WHEN** `/repo/sub/morphir.toml` sets `metadata.lock = "deps.lock"`
- **AND** the target field holds a text value with its origin
- **THEN** the field holds `"deps.lock"` and an origin that names `/repo/sub/morphir.toml`

### Requirement: Binding is pure
Binding SHALL use only the given configuration and arguments. It SHALL NOT read
files, environment variables or the clock. It SHALL give the same result for the
same inputs on the wasm, wasm-gc, js and native targets.

#### Scenario: Same result on all targets
- **WHEN** the acceptance suite binds one in-memory configuration on each of the four targets
- **THEN** each target gives equal bound values and equal error texts
