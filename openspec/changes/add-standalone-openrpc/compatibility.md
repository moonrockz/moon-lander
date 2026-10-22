# OpenRPC evidence and acceptance matrix

## Evidence boundary

Reviewed on 2026-10-21. The Smithy evidence checkout is
`/home/damre/orca/workspaces/smithy/bristleworm`, remote
`https://github.com/moonrockz/smithy.git`, HEAD
`c36698b3bd08be62d5d80e93b727ce736388adf6` at initial inspection. It is read-only. Do not run its build
tasks here, change its dependency graph, or use its generated outputs as proof
of the new library. Its existing tests are requirements evidence, not new test
results. The eventual migration needs a separate workspace and change.

The live checkout advanced during this investigation to
`fc9669a76c8db0e21ee6f42be58749baedad44f6` and had unrelated runtime RPC work in
progress. A read-only diff of every path listed below against the pinned baseline
showed no changes. Use the pinned baseline for reproducible OpenRPC evidence;
do not reset or clean the live checkout. This workspace made no edits there.

## Reviewed Smithy sources

| Source | Evidence used |
| --- | --- |
| `pkgs/smithy-openrpc/README.mbt.md` | Public contract, distinct versions, policies, runtime boundary, qualification |
| `types.mbt`, `config.mbt` | `Conversion`, warning codes and ShapeId, typed settings, accepted document/protocol versions |
| `converter.mbt`, `converter_test.mbt` | Descriptor order, successful results, components, titles, descriptions, direct selectors, null and empty objects |
| `schema.mbt`, `schema_test.mbt` | Draft-07 schema selection, recursive references, exact tokens, disabled defaults, schema-aware traversal, custom schema annotations |
| `examples.mbt`, `examples_test.mbt` | Runtime-checked examples, either-mode interior holes, named metadata, error examples and failures |
| `tests/features/openrpc.feature`, `tests/bdd/openrpc_world_wbtest.mbt` | Complete service export and shape-linked failure cases |
| `tests/tck/openrpc/README.md` and all three JSON assets | Frozen independent conformance oracle and companion alias |
| `scripts/test-openrpc.mbtx` | Digest checks, Ajv, isolated consumers, CLI aliases, failure exit status, schema/runtime agreement |
| `apps/smithy/openrpc_plugin_wbtest.mbt` | Deterministic artifact name and invalid-selection behavior |
| `examples/openrpc/main.mbtx`, `model.smithy`, `smithy-build.json` | Exact pinned consumer imports, representative calculator and build configuration |

## Official sources and pins

| Source | Version or identity | Purpose |
| --- | --- | --- |
| [OpenRPC 1.3.2 prose](https://github.com/open-rpc/spec/blob/df0df86da41d3a67b35a4b320067748344e035b5/spec.md) | Tag `1.3.2`, commit `df0df86da41d3a67b35a4b320067748344e035b5` | Normative 1.3.2 model and semantic rules |
| [OpenRPC meta-schema release](https://github.com/open-rpc/meta-schema/releases/tag/1.14.9) | Asset release `1.14.9`, not a document version | Smithy artifact conformance oracle |
| [OpenRPC 1.4 template](https://github.com/open-rpc/spec/blob/876aa30e341f7669f5ba261e89520a5fc3057038/spec/1.4/spec-template.md) and [schema](https://github.com/open-rpc/spec/blob/876aa30e341f7669f5ba261e89520a5fc3057038/spec/1.4/schema.json) | Commit `876aa30e341f7669f5ba261e89520a5fc3057038` | 1.4.x source and compatibility-line rule |
| [Draft-07 core](https://json-schema.org/draft-07/draft-handrews-json-schema-01) and [validation](https://json-schema.org/draft-07/draft-handrews-json-schema-validation-01) | Draft-07 | Schema documents, keyword forms, scopes, references, annotations |
| [Draft-07 metaschema](https://json-schema.org/draft-07/schema) | Freeze exact asset in story 1 | Schema-document validation oracle |
| [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) and [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901) | URI and JSON Pointer | Structured reference syntax and resolution |
| [JSON-RPC 2.0](https://www.jsonrpc.org/specification) | Protocol `2.0` | Boundary between document and runtime protocol validation |

Verified Smithy frozen asset SHA-256 values:

- `open-rpc-meta-schema.json`:
  `e5f534fb0dd9dd3598d26414e278a8c96e923ee7b54bef7009c499f4c71d0f82`.
- `json-schema-meta.json`:
  `c60549433ca5726bb3ff8959bbcdb3013b6b17fd8c3f99ae0c9604088c714738`.
- The alias maps `https://meta.json-schema.tools` to
  `https://meta.json-schema.tools/`, without editing either upstream document.

The inspected 1.4 schema SHA-256 is
`a8a733cd87ef6ba2e1a38e6500090581b0f52b91051a0bad8386004366b11c56`.
The 1.4 template SHA-256 is
`70efadbae60557578d689f225f1edcb9d0f56b9b4d49c3a3e79a42ba934f46df`.
The 1.3.2 prose SHA-256 is
`5a2ec1ec2cb5ba6dcf4ba642d71f4b6027a234312995a2a201ececacf2c385f2`.
These are inspected inputs. Check them again when freezing test assets. Record
the official draft-07 asset checksum then. Preserve source licenses.

## Downstream acceptance

Each row is required. The local library suite covers document behavior; the
separate Smithy migration must also run its original qualification commands.

| ID | Required behavior | Library evidence | Smithy migration evidence |
| --- | --- | --- | --- |
| S01 | OpenRPC 1.3.2, JSON-RPC 2.0, draft-07, and independent `info.version` | Version matrix and writer retention | Existing default and override settings tests |
| S02 | `convert_result` returns Json plus structured shape-linked warnings; `convert` returns Json | Runnable exact core-Json boundary example | Preserve public signatures or obtain an explicit versioned migration decision |
| S03 | Named, positional, and either structures retain explicit order | AST/read/write order laws, no sorting | Existing positional and naming-policy tests |
| S04 | Optional interior parameters retain `required:false` | Specification error and compatibility warning for the same unchanged input | Existing prepared runtime contract and extension example tests |
| S05 | Successful results include selected scalar, structure, empty object, or explicit null | Distinct absent/result-null/empty-object fixtures | Required-success result and example tests |
| S06 | Complete component refs and recursive schemas, including boolean schemas | Schema-aware graph tests, missing and wrong-kind targets | Existing reference closure qualification |
| S07 | Exact large integers, decimals, exponents, and no default insertion | Exact number laws across all targets | Existing exact numeric examples plus decimal regression fixtures |
| S08 | Titles, summaries, descriptions, deprecation and naming/timestamp choices survive | Full typed field inventory and round-trip cases | Existing options and schema-policy tests |
| S09 | Arbitrary `x-*`, including null, nested values and literal `$ref`, survive | Every extensible object and exact-value retention | Preserve root `x-smithy-protocol`, method `x-smithy-error-data`, `x-smithy-error-examples`, example `x-smithy-param-structure` |
| S10 | Error `data` is an instance value; extension-held schemas can be checked explicitly | No implicit traversal of data; explicit schema-at-pointer API | Existing error schema/runtime checks and literal `$ref` tests |
| S11 | Preserve/omit/fail policies and structured losses stay in the adapter | No Smithy policy enum, name matching, or import | All current warning codes, subjects, rejection and omission cases |
| S12 | Standard success pairings and extension error pairings retain meaning | Full example model and no invented standard error field in 1.3.2 | Runtime validates modeled examples before export |
| S13 | Pure deterministic processing, without reference fetch or execution | Repeated output, hostile URLs, explicit resources and dependency audit | Repeated build output and aliases agree |
| S14 | Independent official conformance and embedded draft-07 checks | Frozen 1.3.2 and 1.4 oracles plus documented discrepancies | Existing `mise run test:openrpc` with exact published import |
| S15 | Plugin aliases, invalid settings, missing service and failed build status remain | No library CLI or plugin dependency | Existing plugin tests and no-artifact-on-failure checks |
| S16 | Representative parameter/result/error schemas agree with runtime validator | Document suite does not claim envelope validation | Existing Ajv versus actual RPC CLI comparisons |
| S17 | Native, wasm, js and wasm-gc standalone consumers stay independent | Four-target packaged and published consumers with graph audit | Existing isolated consumer across all four targets |
| S18 | Existing no-Ion/WIT/WAC/wasm-devkit isolation remains deliberate | Module graph excludes those dependencies | Existing consumer audit must pass unchanged or report an approved public change |

## Full-model and discrepancy acceptance

Smithy coverage alone cannot qualify the module. Add positive and negative tests
for all seven component tables, method references, contacts, licenses, external
documentation, server variables, link params and servers, tags, external
examples, pairings, schema keyword alternatives, and extensions at each site.

Pin expected outcomes separately for normative rules and each metaschema. The
initial discrepancy inventory is:

| Case | Pinned source difference | Required treatment |
| --- | --- | --- |
| Optional interior params | 1.3.2 prose forbids them; metaschema does not encode the rule | Preserve order; Specification error, compatibility warning |
| Server and license names | 1.3.2 prose requires them; artifact required lists omit them | Store presence; report profile/facet result |
| Example external URL | Prose defines `externalValue` and mutual exclusion; artifact requires `value` | Typed external alternative, no fetching; separate oracle result |
| Tag/pairing summaries | 1.3.2 prose defines fields omitted from artifact properties | Retain typed fields and versioned conformance evidence |
| Pairing component name | 1.3.2 prose uses `examplePairingObjects`; artifact uses `examplePairings` | Preserve actual wire table and pointers, never silently rename |
| Component key grammar | Prose anchors a restricted key grammar; artifact uses a loose `[0-z]+` pattern | Checked keys and explicit normative finding |
| OpenRPC reference siblings | Prose ignores added fields; artifact forbids them | Preserve in CST, ignore during resolution, report artifact rejection |
| 1.4 patch spelling | Artifact regex permits leading zeroes; SemVer does not | Canonical version constructor rejects non-SemVer spellings |
| Weaker 1.4 field types | 1.4 artifact omits some types, including info/link object and link name | Typed AST requires correct kinds; do not inherit oracle omissions |

Do not backport newly changed fields from the mutable 1.3 branch into the frozen
1.3.2 model. In particular, a later prose addition of standard error examples
does not change Smithy's 1.3.2 extension contract.

The pinned 1.4 prose is built from its schema and template. The official
[markdown builder](https://github.com/open-rpc/spec/blob/876aa30e341f7669f5ba261e89520a5fc3057038/src/build-markdown.ts)
extracts field tables and required markers from `properties` and `required`.
The model retains the union of fields, while conformance rules stay versioned.
In particular, 1.4 omits required markers for server, license and link names;
the typed model retains their presence. The 1.3.2 prose requires these names.
Only server/license omissions belong to the approved compatibility downgrade
list. A missing link name remains an error for 1.3.2. Prose-only 1.3.2 fields
must not be silently treated as 1.4 normative fields when its generated tables
omit them. The separate artifact facet still uses the exact pinned schema.

## Rollout evidence to collect

The release-candidate record must identify the source SHA, shared package version,
archive checksum, API inventory, license/dependency audit, four-target outputs,
OpenSpec checks, and package dry run. A loopback registry proves the packaged
candidate only. Publication requires an explicit approval tied to that candidate.
After upload, record public resolution of the exact archive outside `moon.work`.

Only then create a separate Smithy migration workspace. Record its base and
migration SHAs, exact published import, compatibility results for S01-S18, and
rollback commit. Keep migration and release gates open until their own evidence
exists. No local-path override or old Smithy test result can close them.
