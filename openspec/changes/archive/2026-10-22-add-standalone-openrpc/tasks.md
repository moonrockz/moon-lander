# Tasks: add-standalone-openrpc

Epic: `lander-bwk`. Design approval: `lander-bwk.1`.

The owner authorized this proposal and tracking. Implementation starts after
the concrete design is approved. Each numbered group is one beads story. Claim
one story, implement and verify it, then tick its tasks and close that story.
Each story carries its own tests and runnable documentation. Run formatting,
`mise run check`, and strict OpenSpec validation before closing local code work.
Publication and the downstream migration need their own evidence as stated below.

## 1. Prove a thin path through both supported version lines

Bead: `lander-bwk.2`
Depends on: `lander-bwk.1`.

- [x] 1.1 Register `pkgs/openrpc` with the root version and prove proposed operation signatures in a runnable consumer without framework, Smithy, Ion, UI, or host imports.
- [x] 1.2 Freeze licensed 1.3.2/1.4 and draft-07 qualification inputs with provenance and SHA-256 checks; verify the known Smithy digests and document source discrepancies.
- [x] 1.3 Prove strict parse, unchanged CST reproduction, typed reading, validation, a recursive local schema ref, extension retention, exact decimal/large integer retention, canonical output, and a structured negative case on native, wasm, js, and wasm-gc.
- [x] 1.4 Fix documented default resource bounds and demonstrate typed exhaustion and stack safety in the tracer; pass focused tests, full check, and strict OpenSpec validation before closing this story.

## 2. Complete exact JSON, domain values, and source mapping

Bead: `lander-bwk.3`
Depends on: `lander-bwk.2`.

- [x] 2.1 Complete strict JSON CST nodes, member occurrences, punctuation, trivia, raw tokens and UTF-16 spans; verify malformed syntax, escaped duplicate keys, CRLF and non-BMP cases on all targets.
- [x] 2.2 Complete immutable exact JSON and checked domain types with lexical and exact numeric comparisons; verify decimals, huge exponents, negative zero, invalid constructors and collection mutation resistance.
- [x] 2.3 Complete SourceMap and explicit core-Json interop; run documented examples and retention/limit laws, and prove no interop path claims to recover digits already discarded by a caller.

## 3. Model complete draft-07 schemas

Bead: `lander-bwk.4`
Depends on: `lander-bwk.3`.

- [x] 3.1 Implement typed boolean/object schemas and every draft-07 keyword alternative; verify the executable keyword inventory against frozen sources with positive and negative decoding cases.
- [x] 3.2 Preserve exact bounds, annotations, unknown keywords, dictionary keys, literal data and explicit dialect declarations; verify schema read/write laws on all targets.
- [x] 3.3 Add runnable schema construction and traversal documentation; verify examples and prove schema versus instance-value traversal boundaries.

## 4. Model the full OpenRPC document

Bead: `lander-bwk.5`
Depends on: `lander-bwk.3`, `lander-bwk.4`.

- [x] 4.1 Complete typed root, info, contact, license, docs, servers/variables, methods, descriptors, tags, links/servers, errors, examples/pairings and all reference sites; verify both version field inventories.
- [x] 4.2 Complete all seven component categories, prose-only fields, historical table spellings, first-class extensions and retained additional fields; verify full-model round trips without reference renaming.
- [x] 4.3 Add runnable producer examples and verify missing/present false/empty/null distinctions, notification-result distinction and immutable public collections on all targets.

## 5. Validate schema documents and regex syntax

Bead: `lander-bwk.6`
Depends on: `lander-bwk.4`.

- [x] 5.1 Validate draft-07 keyword shapes, exact constraints and dialect support; compare positive/negative schema documents with the frozen metaschema and document supported URI aliases.
- [x] 5.2 Check ECMA-262 regex syntax portably, including constructs outside the installed regexp matcher subset; verify conformance cases on every target without adding an instance evaluator.
- [x] 5.3 Expose explicit schema validation at an extension path/base; verify that literal data and arbitrary extension schemas are never inferred or walked, and run documented adapter-neutral examples.

## 6. Resolve references through explicit resource snapshots

Bead: `lander-bwk.7`
Depends on: `lander-bwk.4`, `lander-bwk.5`.

- [x] 6.1 Complete structured RFC 3986 references and RFC 6901 pointers; verify relative paths, empty fragments, percent and tilde escapes, arrays, missing bases and invalid syntax.
- [x] 6.2 Implement immutable resources, nested draft-07 IDs/fragments, target-kind checks and graph traversal; verify recursive schemas, reference-only cycles, conflicting IDs, missing resources and bounded traversal.
- [x] 6.3 Add local/external-resource examples and verify that hostile reference URLs, server templates, external examples and literal `$ref` values cause no host I/O or code execution.

## 7. Validate document semantics and coverage

Bead: `lander-bwk.8`
Depends on: `lander-bwk.5`, `lander-bwk.6`, `lander-bwk.7`.

- [x] 7.1 Implement versioned normative and pinned-artifact rules with structured, ordered diagnostics; verify required fields, key grammar, duplicates, server variables, links and parameter order after resolution.
- [x] 7.2 Implement Specification and bounded MetaschemaCompatibility profiles; verify all discrepancy outcomes, report-only `validate`, gated `validate_closed`, and no wrapper for failed/incomplete required checks.
- [x] 7.3 Document profile and protocol boundaries with runnable examples; verify generated-AST pointers, source-related locations, reference chains, exhaustion and cross-target diagnostic equality.

## 8. Complete writing and source-preserving value edits

Bead: `lander-bwk.9`
Depends on: `lander-bwk.5`.

- [x] 8.1 Complete canonical compact and explicit pretty writing, with UTF-16 object-key ordering, exact number tokens and unchanged array order; verify full AST laws and identical four-target output.
- [x] 8.2 Add checked replacement of an existing CST value span and fresh read/source-map results; verify unchanged surrounding source, stale-node rejection and invalid replacement failure.
- [x] 8.3 Run editor and writer documentation examples; verify default omission, extension retention, reference spelling and explicit source-reproduction/JCS distinctions.

## 9. Qualify the full library and Smithy compatibility corpus

Bead: `lander-bwk.10`
Depends on: `lander-bwk.8`, `lander-bwk.9`.

- [x] 9.1 Add full-model and S01-S18 acceptance coverage under the unpublished tests module, with independent frozen Ajv checks and separate normative/artifact discrepancy expectations.
- [x] 9.2 Add pinned MoonBit qualification scripts and mise/CI tasks; verify both version lines on four targets and deliberate invalid-document, invalid-ref, digest-mismatch and task-failure exits.
- [x] 9.3 Record complete field/keyword coverage and exact-number evidence beyond Ajv, pass full workspace checks and strict validation, and identify Smithy-only parity work still pending.

## 10. Prepare the independently packaged release candidate

Bead: `lander-bwk.11`
Depends on: `lander-bwk.10`.

- [x] 10.1 Finish runnable public API docs, dependency/license audit, release notes and shared-version validation; pass deterministic `moon -C pkgs/openrpc package` and the loopback registry check without publishing, and add the GitHub Actions release workflow (credentials only in CI, so the authenticated publish runs there).
- [x] 10.2 Adapt the existing MoonBit isolated-registry consumer pattern and verify the packaged archive outside `moon.work` on all four targets, including dependency leak rejection.
- [x] 10.3 Record candidate source SHA, exact version, archive SHA-256, graph and complete command results; prepare the concrete approval request and label loopback results as pre-publication evidence.

## 11. Obtain publication approval and prove the public dependency

Bead: `lander-bwk.12`
Depends on: `lander-bwk.11`.

- [x] 11.1 Obtain explicit owner approval for the concrete candidate's publication and GitHub release by the owner merging the release pull request; record the approved version, source SHA and archive identity before the workflow publishes.
- [x] 11.2 After the merge, let the release workflow upload the unchanged verified package and run a fresh exact-version public-registry consumer outside `moon.work` on all four targets without overrides or local substitution, against the archive checksum it built.
- [x] 11.3 Record public resolution, checksum and source identity; keep this gate open if approval, artifact identity or any target proof is absent or fails, and obtain separate release authority when it was not included.

## 12. Migrate Smithy in its own workspace and prove parity

Bead: `lander-bwk.13`
Depends on: `lander-bwk.12`.

- [x] 12.1 Arrange a separate Smithy migration workspace from the recorded baseline, add its own tracked change and exact published import, and verify that migration work makes no edits in the active bristleworm checkout.
- [x] 12.2 Replace shared OpenRPC work behind the existing adapter while retaining its public Json/warning/error APIs and loss policies; verify each compatibility matrix row or document an explicitly approved public change.
- [x] 12.3 Pass existing unit, plugin, isolated-consumer and `mise run test:openrpc` qualification on all four targets, and BDD features on native, wasm and js, using the published dependency; record source and rollback SHAs before closing the rollout.

## Workflow follow-up

- Keep the proposal unarchived while implementation or rollout gates remain open.
- Archive after merge and verified completion according to CONTRIBUTING.md.
- Keep local `docs/superpowers/` plans out of staging and commits.
