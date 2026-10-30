# framework-publication Specification

## Purpose

Publish every Moon-Lander library at one shared version while keeping tests and
tooling out of the registry. Verify the exact archives through isolated consumers
before a release is promoted.

## Requirements

### Requirement: Publish every framework library

The release SHALL publish moonrockz/moon-lander-core, moonrockz/moon-lander-logging, moonrockz/moon-lander-config, moonrockz/moon-lander-mediator, moonrockz/moon-lander-logging-hosting-async, moonrockz/moon-lander-actors, moonrockz/moon-lander-hosting, moonrockz/moon-lander, moonrockz/notebooks, moonrockz/openrpc and moonrockz/sigstore at the shared version. Dependencies SHALL publish before dependents. Published sibling imports MUST use that version without local paths.

#### Scenario: Prepare a release

- **WHEN** GitHub Actions publishes an approved version change
- **THEN** all eleven library modules publish in dependency order with exact sibling versions

#### Scenario: Actors candidate consumer

- **WHEN** the candidate archive gate checks actors outside the checkout with isolated caches
- **THEN** its policy consumer builds on wasm, wasm-gc, js and native, and its runtime consumer builds on wasm, js and native without workspace overrides

#### Scenario: Sigstore candidate consumer

- **WHEN** the candidate archive gate checks sigstore outside the checkout with isolated caches
- **THEN** a consumer that verifies one vendored bundle builds on wasm, wasm-gc, js and native without workspace overrides

### Requirement: Exclude tooling and test modules

The release SHALL use an explicit publication allowlist. The workspace root, tests, docs tool and generated consumer or fixture modules MUST be private and MUST NOT publish.

#### Scenario: A tooling module enters the workspace

- **WHEN** a module outside the publication allowlist is not private
- **THEN** policy validation fails before publication

### Requirement: Verify registry consumers

The release SHALL verify each library from candidate archives before publication and from the public registry after publication, outside the checkout with isolated caches and no workspace overrides. Portable consumers SHALL build on wasm, wasm-gc, js and native. Target-limited adapters SHALL build on their supported targets. Public archive checksums MUST match the approved candidate checksums. Public format override qualification MUST pass before GitHub release creation.

#### Scenario: A package misses required files

- **WHEN** an archive omits a license, manifest or required adapter source
- **THEN** candidate audit or consumer compilation fails

#### Scenario: A public archive differs

- **WHEN** a downloaded release archive checksum differs from the approved candidate
- **THEN** the published check fails and the GitHub release is blocked
