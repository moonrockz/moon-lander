# Framework publication specification delta

## MODIFIED Requirements

### Requirement: Publish every framework library

The release SHALL publish moonrockz/moon-lander-core, moonrockz/moon-lander-logging, moonrockz/moon-lander-config, moonrockz/moon-lander-mediator, moonrockz/moon-lander-logging-hosting-async, moonrockz/moon-lander-actors, moonrockz/moon-lander-hosting, moonrockz/moon-lander, moonrockz/notebooks and moonrockz/openrpc at the shared version. Dependencies SHALL publish before dependents. Published sibling imports MUST use that version without local paths.

#### Scenario: Prepare a release

- **WHEN** GitHub Actions publishes an approved version change
- **THEN** all ten library modules publish in dependency order with exact sibling versions

#### Scenario: Actors candidate consumer

- **WHEN** the candidate archive gate checks actors outside the checkout with isolated caches
- **THEN** its policy consumer builds on wasm, wasm-gc, js and native, and its runtime consumer builds on wasm, js and native without workspace overrides
