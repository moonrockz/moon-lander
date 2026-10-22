# Proposal: add-standalone-openrpc

## Why

OpenRPC reading, writing, and validation are useful without a service framework
or a Smithy model. Host `moonrockz/openrpc` in this repository so MoonBit tools can
share one complete document model and keep the original source when needed.
Smithy will consume the published package through its existing OpenRPC adapter.

## What changes

- Add the independent `moonrockz/openrpc` module at `pkgs/openrpc`, with a pure
  reader, writer, document validator, typed AST, and source-preserving JSON CST.
- Support OpenRPC 1.3.2 and the 1.4.x compatibility line in the first release.
  Cover the complete model, including every component category, references,
  embedded draft-07 schemas, examples, servers, links, and extensions.
- Use checked domain values, exact JSON number tokens, typed references, and
  structured diagnostics. Preserve absent fields and arbitrary extension values.
- Separate source reproduction, deterministic AST writing, schema validation,
  reference resolution, and specification conformance. Report upstream prose and
  metaschema disagreements without changing the input.
- Resolve references only against explicit resources. Keep all processing free
  of network access and document-controlled execution.
- Add unpublished acceptance suites, frozen upstream qualification inputs, and
  MoonBit task scripts. Qualify native, wasm, js, and wasm-gc consumers.
- Prepare a verified package candidate. Keep publication approval, published
  consumer proof, and a separate Smithy migration workspace as explicit gates.

## Capabilities

### New capabilities

- `openrpc-documents`: versioned OpenRPC models, JSON codecs, document and
  embedded-schema validation, source retention, references, and diagnostics.
- `openrpc-rollout`: independent package qualification, release preparation,
  publication gates, and compatibility evidence for the Smithy migration.

### Modified capabilities

None. Existing framework and notebook contracts do not change.

## Impact

Register `pkgs/openrpc` in `moon.work` and use the root module's shared version.
Add acceptance packages under `tests/`, and tasks under `scripts/` exposed through
mise. Audit dependencies before selecting them. Existing Ion and configuration
facilities inform the design but do not become required framework dependencies.

The read-only Smithy baseline is commit
`c36698b3bd08be62d5d80e93b727ce736388adf6`. Its API and acceptance requirements are
recorded in [compatibility.md](compatibility.md).

## Out of scope

- Smithy shape conversion, extension loss policies, or Smithy imports in the library.
- JSON-RPC envelope, notification, batch, response correlation, or exchange validation.
- A general runtime JSON Schema instance-validation engine, code generation,
  link evaluation, network reference retrieval, a CLI, UI, or host adapter.
- Edits to the active Smithy evidence checkout, a local override presented as a
  published dependency, or publication without explicit approval.

## Review state

The owner approved the concrete design after its walkthrough on 2026-10-21:
"okay this looks good". Both 1.3.2 and 1.4.x are first-release requirements.
Other choices remain identified as author calls. Implementation is authorized.
Publication and GitHub release approval remain separate candidate-specific gates.
