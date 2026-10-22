# OpenRPC qualification record

This records the evidence for task group 9 at the commit that adds this file.
Commands run from the workspace root with the pinned toolchain
(`moon 0.10.15`). Results are reproducible with the same commands.

## Commands and results

| Command | Evidence |
| --- | --- |
| `mise run qualify:openrpc` | Frozen asset digests verified; pinned Ajv 8.17.1 agrees with all 30 corpus artifact expectations offline; the library agrees with all 30 expectations (artifact, normative, closed Specification, closed MetaschemaCompatibility) on native, wasm, js and wasm-gc, with byte-identical output across targets |
| `mise run qualify:openrpc-failures` | A wrong closed expectation, a broken-reference expectation, an altered frozen asset and a missing corpus file each exit nonzero with their specific reason; the corpus is unchanged (also run by `test:scripts`) |
| `mise run check:openrpc` | Focused suites and the isolated source consumer agree on all four targets; the 81-case ECMAScript 2018 pattern corpus agrees with pinned regexpp 4.12.2; the 61-case schema-shape corpus agrees with Ajv and the frozen draft-07 metaschema; the dependency graph excludes Smithy, Ion, Moon-Lander, notebooks, async, Rabbita, Proton, wasm-devkit, WIT and WAC |
| `mise run check:openrpc-assets`, `check:openrpc-artifacts`, `check:openrpc-unicode` | Frozen inputs, generated artifact metaschemas and Unicode tables are current |
| `mise run check` | Full workspace gate, including the above |
| `mise exec -- openspec validate --all --strict` | Specifications and this change are valid |

## Corpus

`tests/openrpc-qualification/corpus/cases.json` lists each document with
separate expectations. Every row of the discrepancy table in
[compatibility.md](compatibility.md) has a case on each version line where it
applies: optional-before-required parameters, server and license names (1.3.2),
external examples, tag and pairing summaries, the pairing component spelling,
component key grammar, reference siblings, and 1.4 link names. The full-model
cases cover all seven component tables, method references, contact, license,
external documentation, server variables, link parameters and servers, tags,
examples, pairings, recursive and boolean schemas, and extensions at each
extensible site. Failure cases cover duplicate methods, exact duplicate error
codes, missing link targets, unresolved references and invalid regex syntax.

## Field inventory

Fields each version's pinned tables define. The typed model keeps the union;
members outside a version's table are retained and reported as `UnknownField`
warnings.

| Object | OpenRPC 1.3.2 (prose) | OpenRPC 1.4 (pinned schema) |
| --- | --- | --- |
| Document | `openrpc`, `info`, `methods`, `servers`, `components`, `externalDocs` | `$schema`, `openrpc`, `info`, `methods`, `servers`, `components`, `externalDocs` |
| Info | `title`, `version`, `description`, `termsOfService`, `contact`, `license` | same |
| Contact | `name`, `url`, `email` | same |
| License | `name`, `url` | same |
| ExternalDocumentation | `url`, `description` | same |
| ServerVariable | `default`, `enum`, `description` | same |
| Server | `url`, `name`, `summary`, `description`, `variables` | same |
| Method | `name`, `tags`, `summary`, `description`, `externalDocs`, `params`, `result`, `deprecated`, `servers`, `errors`, `links`, `paramStructure`, `examples` | same |
| ContentDescriptor | `name`, `summary`, `description`, `required`, `schema`, `deprecated` | same |
| Tag | `name`, `summary`, `description`, `externalDocs` | `name`, `description`, `externalDocs` |
| Error | `code`, `message`, `data` | same |
| Example | `name`, `summary`, `description`, `value`, `externalValue` | `name`, `summary`, `description`, `value` |
| ExamplePairing | `name`, `summary`, `description`, `params`, `result` | `name`, `description`, `params`, `result` |
| Link | `name`, `summary`, `description`, `method`, `params`, `server` | same |
| Components | `schemas`, `contentDescriptors`, `examples`, `links`, `errors`, `tags`, `examplePairingObjects` | `schemas`, `contentDescriptors`, `examples`, `links`, `errors`, `tags`, `examplePairings` |
| Reference | `$ref` | same |

`check:openrpc` also compares the unified model inventory with the object
properties of both frozen schemas.

## Draft-07 keywords

The schema-shape corpus exercises every one of the 46 properties of the frozen
draft-07 metaschema, with valid and invalid forms, against pinned Ajv. Regex
syntax for `pattern` and `patternProperties` uses the 81-case corpus compared
with regexpp.

## Exact numbers beyond Ajv

Ajv compares numbers as doubles, so it cannot prove exact behavior. MoonBit
tests on all four targets prove it instead: token retention for
`9007199254740993`, `0.10000000000000000001`, `1e400`, `1e-400` and `-0.00`;
numeric equality that equates `1`, `1.0` and `1e0` and separates `2^53` from
`2^53+1`; duplicate error codes under exact equality; and canonical writing
that keeps each token unchanged.

## S01-S18 library evidence

| Row | Evidence |
| --- | --- |
| S01, S02, S03, S04, S05, S06, S07, S08, S09, S10, S12, S13, S16 | `tests/openrpc-acceptance/s_rows_wbtest.mbt`, tests named by row |
| S11, S15, S18 | No adapter policy, CLI, plugin, Ion, WIT, WAC or wasm-devkit dependency: `check:openrpc` dependency-graph deny-list |
| S14 | `qualify:openrpc` frozen oracles and discrepancy corpus |
| S17 | Four-target isolated consumers in `check:openrpc` and `qualify:openrpc`; packaged and published consumers belong to groups 10 and 11 |

## Pending Smithy-only parity

These need the Smithy migration (group 12) and cannot be closed by library
evidence: preserving `convert_result`/`convert` signatures and shape-linked
warnings (S02, S11); adapter preserve/omit/fail policies and warning codes
(S11); plugin aliases, invalid settings and failed-build status (S15); runtime
agreement between Ajv and the RPC CLI (S16); and Smithy's own
`mise run test:openrpc` with the exact published import (S14, S17).
