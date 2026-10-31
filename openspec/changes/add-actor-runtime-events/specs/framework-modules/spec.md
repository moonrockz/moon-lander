# Framework modules specification delta

## MODIFIED Requirements

### Requirement: Dependency direction

Config, mediator and logging-hosting-async SHALL import only core and logging;
actors only core; hosting only core, logging, config and logging-hosting-async;
the umbrella only those seven modules. Core and logging MUST import only core
standard packages. Actors MUST use no external module except async and
`moonrockz/ion`, and only the `moonrockz/ion/ion` package of Ion. Moonx MUST
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
- **THEN** its dependency graph has no hosting, config, mediator or logging module and no TOML, YAML or JSON5 module

#### Scenario: Actors imports Ion

- **WHEN** `pkgs/actors/moon.mod` imports `moonrockz/ion` and an actors package imports `moonrockz/ion/ion`
- **THEN** `mise run validate` accepts both imports

#### Scenario: Actors imports an Ion encoding package

- **WHEN** a package of `pkgs/actors` imports `moonrockz/ion/text` or another Ion package than `moonrockz/ion/ion`
- **THEN** `mise run validate` fails and names the package and the import

#### Scenario: Actors imports another external module

- **WHEN** `pkgs/actors/moon.mod` imports an external module other than `moonbitlang/async` or `moonrockz/ion`
- **THEN** `mise run validate` fails and names the module

#### Scenario: Actors imports against the direction

- **WHEN** `pkgs/actors/moon.mod` imports hosting or mediator
- **THEN** `mise run validate` fails and names both modules

#### Scenario: Canonical runtime enters the Moonx module

- **WHEN** the Moonx module imports canonical async or a framework module
- **THEN** dependency validation fails and names both modules

#### Scenario: Umbrella imports the optional Moonx runtime

- **WHEN** the umbrella or another framework module imports the Moonx module
- **THEN** dependency validation fails before canonical and compatibility runtimes can be combined
