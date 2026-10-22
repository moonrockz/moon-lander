## ADDED Requirements

### Requirement: Four-target independent qualification

The change SHALL add unpublished acceptance suites and MoonBit task scripts for
both supported version lines. Qualification SHALL cover the full field inventory,
exact-value and source laws, invalid documents, schema documents, reference
graphs, deterministic output, and compatibility rows S01-S18. It MUST use frozen
official inputs with source identities, checksums, licenses, and explicit
prose/metaschema discrepancy expectations.

#### Scenario: Both version lines pass the complete qualification gate

- **WHEN** the library is proposed as a release candidate
- **THEN** native, wasm, js, and wasm-gc tests and consumers pass for both 1.3.2
  and 1.4.x, and the complete field inventory has positive and negative coverage
- **AND** strict OpenSpec validation and `mise run check` pass

#### Scenario: Independent validation has stated limits

- **WHEN** Ajv checks generated documents and embedded schemas against frozen assets
- **THEN** expected artifact outcomes and normative discrepancies are checked separately
- **AND** MoonBit exact-number tests provide evidence beyond binary floating point

### Requirement: Concrete verified release candidate

The package candidate SHALL use the shared workspace version and contain runnable
public API documentation, license information, and an audited dependency graph.
Before publication it MUST pass package dry-run checks and an isolated packaged
consumer outside `moon.work` on every target. The candidate record SHALL include
source SHA, exact version, archive checksum, commands, and results.

#### Scenario: Package contents work outside the monorepo

- **WHEN** an isolated consumer resolves the candidate through a loopback registry
- **THEN** it reads, validates, and writes both supported version lines on all targets
- **AND** the resolved graph excludes framework, Smithy, Ion, UI, and host dependencies
- **AND** the evidence identifies this as packaged-candidate proof only

### Requirement: Explicit publication approval and public dependency proof

Publishing to mooncakes.io or cutting a GitHub release SHALL require explicit
owner approval of a concrete verified candidate. Public dependency qualification
MUST resolve the exact approved version outside the workspace without a path
override or local candidate substitution. Package dry runs and loopback registry
checks MUST NOT count as public-registry proof.

#### Scenario: Candidate preparation does not imply publication authority

- **WHEN** all pre-publication checks pass
- **THEN** the release record is ready for approval and publication has not occurred
- **AND** release and downstream-publication gates remain open until their own
  approval and verification evidence exists

#### Scenario: Published consumer resolves the approved artifact

- **WHEN** the owner approves and the exact candidate is uploaded
- **THEN** a fresh public-registry consumer records its dependency version,
  archive identity, source SHA, and passing results for all targets
- **AND** a mismatched, unavailable, or locally substituted package fails the gate

### Requirement: Deliberate separate-workspace Smithy migration

The rollout SHALL track a separate Smithy migration from the read-only baseline
`c36698b3bd08be62d5d80e93b727ce736388adf6`. That migration MUST consume an exact
published `moonrockz/openrpc` version and prove compatibility with the existing
qualification suite. The active evidence checkout MUST remain unchanged.

#### Scenario: Migration preserves public and adapter behavior

- **WHEN** Smithy's OpenRPC adapter moves to the published module in its own workspace
- **THEN** `convert_result`, `convert`, shape-linked warnings/errors, extension
  loss policies, naming and timestamp settings, examples, and CLI behavior retain
  their existing public contracts or have an explicitly approved versioned change
- **AND** rows S01-S18 have recorded migration evidence

#### Scenario: Existing qualification remains the parity gate

- **WHEN** the migration is proposed as complete
- **THEN** its unit, feature, plugin, isolated-consumer and `mise run test:openrpc`
  checks pass across native, wasm, js, and wasm-gc with the exact public dependency
- **AND** official conformance, embedded schemas, component closure, determinism,
  aliases, failed-build status, and actual runtime RPC agreement retain their checks
- **AND** the record includes baseline, migration, and rollback source identities
