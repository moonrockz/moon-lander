# framework-modules Specification

## Purpose
Framework modules divide Moon-Lander into separate MoonBit modules, so that an
application imports only the parts it uses and shared domain types sit below every
module that uses them.

## Requirements

### Requirement: Framework module set

The workspace SHALL provide eight framework modules: `moonrockz/moon-lander-<name>`
in `pkgs/<name>` for core, logging, config, mediator, hosting,
logging-hosting-async and actors, and `moonrockz/moon-lander` in `pkgs/lander`.
Each MUST be a member of `moon.work`.

#### Scenario: Members of the workspace

- **WHEN** `mise run validate` reads `moon.work`
- **THEN** it finds the eight framework modules in their folders, each with a `moon.mod` that gives its module name

#### Scenario: Old package paths are gone

- **WHEN** a package imports `moonrockz/moon-lander/config` or `moonrockz/moon-lander/hosting`
- **THEN** the build fails, because the module `moonrockz/moon-lander` has no such package

#### Scenario: Logging module is missing from the workspace

- **WHEN** `moon.work` does not list `./pkgs/logging`
- **THEN** `mise run validate` fails and names the folder `pkgs/logging`

#### Scenario: Optional logging runtime module is missing from the workspace

- **WHEN** `moon.work` does not list `./pkgs/logging-hosting-async`
- **THEN** `mise run validate` fails and names the folder `pkgs/logging-hosting-async`

#### Scenario: Optional actors module is missing from the workspace

- **WHEN** `moon.work` does not list `./pkgs/actors`
- **THEN** `mise run validate` fails and names the folder `pkgs/actors`

### Requirement: Main package at the module root

The main package of each framework module SHALL be the root package of the module.
Other packages of the module SHALL be below it, for example
`moonrockz/moon-lander-config/conventions` and `moonrockz/moon-lander-hosting/console`.

#### Scenario: Configuration core path

- **WHEN** an application imports `moonrockz/moon-lander-config`
- **THEN** it gets the configuration builder, sources, binding and errors

#### Scenario: Format parser path

- **WHEN** an application imports `moonrockz/moon-lander-config/parsers/yaml`
- **THEN** it gets the YAML format descriptor

#### Scenario: Async mediator path

- **WHEN** an application imports `moonrockz/moon-lander-mediator/async`
- **THEN** it gets the async senders, topics and middleware

### Requirement: Dependency direction

A framework module SHALL import only the framework modules below it: config,
mediator and logging-hosting-async import core and logging; actors imports core;
hosting imports core, logging, config and logging-hosting-async;
`moonrockz/moon-lander` can import all seven. Core and logging MUST import no
module except `moonbitlang/core`. Logging-hosting-async and actors MAY import
`moonbitlang/async`; actors MUST NOT import another external module.

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

#### Scenario: Standalone async sinks do not resolve the application host

- **WHEN** an isolated consumer imports `moonrockz/moon-lander-logging-hosting-async/runtime`
- **THEN** its resolved dependencies contain neither `moonrockz/moon-lander-config` nor `moonrockz/moon-lander-hosting`

#### Scenario: Logging runtime imports against the direction

- **WHEN** the `moon.mod` of `pkgs/logging-hosting-async` imports configuration or hosting
- **THEN** `mise run validate` fails and names both modules

#### Scenario: Hosting uses the standalone logging runtime

- **WHEN** `pkgs/hosting` imports `moonrockz/moon-lander-logging-hosting-async`
- **THEN** dependency validation accepts that direction and the logging runtime module does not import hosting

#### Scenario: Standalone actor consumer

- **WHEN** an isolated consumer imports `moonrockz/moon-lander-actors/runtime`
- **THEN** its dependency graph has no hosting, config, mediator, logging or parser module

#### Scenario: Actors imports against the direction

- **WHEN** `pkgs/actors/moon.mod` imports hosting or mediator
- **THEN** `mise run validate` fails and names both modules

### Requirement: One version for the framework modules

The eight framework modules SHALL have the version of the root `moon.mod`. Each import
of one framework module by another MUST use that version.

#### Scenario: Version drift

- **WHEN** `pkgs/mediator/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

#### Scenario: Set the version

- **WHEN** a maintainer runs `moonx scripts/versions.mbtx set 0.4.0`
- **THEN** the eight framework modules and each import of one by another get `0.4.0`

#### Scenario: Optional logging runtime version drift

- **WHEN** `pkgs/logging-hosting-async/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

#### Scenario: Actors version drift

- **WHEN** `pkgs/actors/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

### Requirement: Shared names live in core

The application name SHALL be a core type with the same rules as before the move. The
host builder MUST take the core type. A module below hosting MUST be able to use the
type without an import of hosting.

#### Scenario: Host builder takes the core name

- **WHEN** an application parses `acme` as a core application name and gives it to the host builder
- **THEN** the builder accepts it without a conversion

#### Scenario: Configuration can use the name

- **WHEN** a package of `moonrockz/moon-lander-config` imports the core application name
- **THEN** it builds, and `moonrockz/moon-lander-config` does not import `moonrockz/moon-lander-hosting`

#### Scenario: Application name error

- **WHEN** an application parses `9acme` as an application name
- **THEN** the parse fails with a core error that holds the text `9acme` and the rule that the first character must be an ASCII letter, as an enum case and not only as message text
