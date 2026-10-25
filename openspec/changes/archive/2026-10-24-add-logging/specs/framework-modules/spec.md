# Spec Delta

## MODIFIED Requirements

### Requirement: Framework module set

The workspace SHALL provide six framework modules: `moonrockz/moon-lander-core` in
`pkgs/core`, `moonrockz/moon-lander-logging` in `pkgs/logging`,
`moonrockz/moon-lander-config` in `pkgs/config`, `moonrockz/moon-lander-mediator` in
`pkgs/mediator`, `moonrockz/moon-lander-hosting` in `pkgs/hosting` and
`moonrockz/moon-lander` in `pkgs/lander`. Each MUST be a member of `moon.work`.

#### Scenario: Members of the workspace

- **WHEN** `mise run validate` reads `moon.work`
- **THEN** it finds the six framework modules in their folders, each with a `moon.mod` that gives its module name

#### Scenario: Old package paths are gone

- **WHEN** a package imports `moonrockz/moon-lander/config` or `moonrockz/moon-lander/hosting`
- **THEN** the build fails, because the module `moonrockz/moon-lander` has no such package

#### Scenario: Logging module is missing from the workspace

- **WHEN** `moon.work` does not list `./pkgs/logging`
- **THEN** `mise run validate` fails and names the folder `pkgs/logging`

### Requirement: Dependency direction

A framework module SHALL import only the framework modules below it: core and logging
import none, config and mediator import only core and logging, hosting imports only
core, logging and config, and `moonrockz/moon-lander` can import all five. Core and
logging MUST import no module except `moonbitlang/core`.

#### Scenario: Mediator without configuration parsers

- **WHEN** a consumer module imports only `moonrockz/moon-lander-mediator`
- **THEN** its resolved dependencies hold no TOML, YAML, JSON5 or Ion module

#### Scenario: Core has no third-party dependency

- **WHEN** a consumer module imports only `moonrockz/moon-lander-core`
- **THEN** its resolved dependencies hold no module except `moonrockz/moon-lander-core`

#### Scenario: Logging has no third-party dependency

- **WHEN** a consumer module imports only `moonrockz/moon-lander-logging`
- **THEN** its resolved dependencies hold no module except `moonrockz/moon-lander-logging`

#### Scenario: Import against the direction

- **WHEN** the `moon.mod` of `pkgs/config` imports `moonrockz/moon-lander-hosting`
- **THEN** `mise run validate` fails and names both modules

#### Scenario: Logging imports a framework module

- **WHEN** the `moon.mod` of `pkgs/logging` imports `moonrockz/moon-lander-core`
- **THEN** `mise run validate` fails and names both modules

#### Scenario: Core imports a third-party module

- **WHEN** the `moon.mod` of `pkgs/core` imports `moonrockz/ion`
- **THEN** `mise run validate` fails and names the module

#### Scenario: Logging imports a third-party module

- **WHEN** the `moon.mod` of `pkgs/logging` imports `moonbitlang/async`
- **THEN** `mise run validate` fails and names the module

### Requirement: One version for the framework modules

The six framework modules SHALL have the version of the root `moon.mod`. Each import
of one framework module by another MUST use that version.

#### Scenario: Version drift

- **WHEN** `pkgs/mediator/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

#### Scenario: Set the version

- **WHEN** a maintainer runs `moonx scripts/versions.mbtx set 0.4.0`
- **THEN** the six framework modules and each import of one by another get `0.4.0`
