## MODIFIED Requirements

### Requirement: Browser support has a required execution gate

The framework SHALL keep a real-browser harness and CI gate, and each backend
story SHALL add its acceptance coverage to it. The framework SHALL keep all
existing checks, validate generated FFI freshness, and verify portable core
behavior on all four MoonBit targets. Missing required engines or tests MUST fail
rather than skip. The pull-request gate SHALL run Chromium and Firefox. A
scheduled or manual workflow and release validation SHALL run Chromium, Firefox,
and WebKit.

#### Scenario: A browser regression blocks merge

- **WHEN** Chromium or Firefox fails a selected browser assertion or cannot run in a pull request
- **THEN** the browser task exits nonzero and `ci-ok` cannot succeed

#### Scenario: A WebKit regression fails the nightly run and the release

- **WHEN** WebKit fails a selected browser assertion or cannot run
- **THEN** the browser task of the nightly workflow and of release validation exits nonzero

#### Scenario: Generated browser code is stale

- **WHEN** a TypeScript behavior change is not reflected in the checked-in browser FFI
- **THEN** the freshness check exits nonzero without rewriting the generated file

#### Scenario: Equivalent snapshots have equivalent results

- **WHEN** the same snapshot, formats, variable map, working directory, and ordered sources load in browser js and in the four core targets
- **THEN** values, origins, reports, and representative typed failures agree

#### Scenario: An ordinary consumer does not import browser support

- **WHEN** an unrelated consumer builds without the browser package
- **THEN** it needs neither browser APIs nor browser adapter build tooling
