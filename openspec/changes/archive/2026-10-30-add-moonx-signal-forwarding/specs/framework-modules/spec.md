# Spec Delta

## MODIFIED Requirements

### Requirement: Framework module set

The workspace SHALL provide nine framework modules: `moonrockz/moon-lander-<name>`
in `pkgs/<name>` for core, logging, config, mediator, hosting,
logging-hosting-async, actors and moonx, and `moonrockz/moon-lander` in `pkgs/lander`.
Each MUST be a member of `moon.work`.

#### Scenario: Members of the workspace

- **WHEN** `mise run validate` reads `moon.work`
- **THEN** it finds the nine framework modules in their folders, each with a `moon.mod` that gives its module name

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

#### Scenario: Optional Moonx module is missing from the workspace

- **WHEN** `moon.work` does not list `./pkgs/moonx`
- **THEN** `mise run validate` fails and names the folder `pkgs/moonx`

### Requirement: Dependency direction

Config, mediator and logging-hosting-async SHALL import only core and logging;
actors only core; hosting only core, logging, config and logging-hosting-async;
the umbrella only those seven modules. Core and logging MUST import only core
standard packages. Actors MUST use no external module except async. Moonx MUST
import no framework module or canonical async. Other framework modules MUST NOT
import moonx. Logging-hosting-async MAY import async.

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

#### Scenario: Canonical runtime enters the Moonx module

- **WHEN** the Moonx module imports canonical async or a framework module
- **THEN** dependency validation fails and names both modules

#### Scenario: Umbrella imports the optional Moonx runtime

- **WHEN** the umbrella or another framework module imports the Moonx module
- **THEN** dependency validation fails before canonical and compatibility runtimes can be combined

### Requirement: One version for the framework modules

The nine framework modules SHALL have the version of the root `moon.mod`. Each
import of one framework module by another MUST use that version.

#### Scenario: Version drift

- **WHEN** `pkgs/mediator/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

#### Scenario: Set the version

- **WHEN** a maintainer runs `moonx scripts/versions.mbtx set 0.4.0`
- **THEN** the nine framework modules and each import of one by another get `0.4.0`

#### Scenario: Optional logging runtime version drift

- **WHEN** `pkgs/logging-hosting-async/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

#### Scenario: Actors version drift

- **WHEN** `pkgs/actors/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions

#### Scenario: Moonx version drift

- **WHEN** `pkgs/moonx/moon.mod` has another version than the root `moon.mod`
- **THEN** `mise run validate:versions` fails and names the file and both versions
