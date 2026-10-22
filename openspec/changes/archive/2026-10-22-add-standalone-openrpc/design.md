# Design: add-standalone-openrpc

## Context

See [proposal.md](proposal.md) for purpose and scope. The requirements are in
`specs/openrpc-documents/spec.md` and `specs/openrpc-rollout/spec.md`.
[compatibility.md](compatibility.md) records the downstream evidence and source
inventory. This design is proposed, not an implemented API.

The pinned MoonBit core exposes `Json::Number(Double, repr? : String)`. Its parser
keeps text for some numbers, but normal decimal and exponent parsing can discard
it. Core JSON maps also discard duplicate object members. Those values cannot
provide a source CST or guarantee exact input decimals.

Moon-Lander uses `moonrockz/ion@0.6.0`. Its `json.read_json` decodes through core
scalar JSON and converts exponent spellings to Ion floats. Its `text.parse_cst`
reads the Ion grammar and omits trivia from the CST. Its `schema` package is an
Ion Schema validator. The configuration JSON5 adapter intentionally converts
numbers through doubles. None provides the complete required JSON contract.

## Goals / non-goals

Make the portable document library useful to producers, validators, and editors.
Keep the semantic model independent of source ownership and of Smithy. A caller
can construct an AST without fabricating source spans or serializing through a
framework configuration value. A source reader can retain a document that fails
OpenRPC validation without representing it as a valid AST.

Schema validation here checks schema documents and their references. It does not
apply those schemas to request, response, or example instances. Do not claim that
document conformance establishes runtime protocol correctness.

## Decisions

### D1. Version support and authority

**Owner:** the first release supports OpenRPC 1.3.2 and 1.4.x. Both use draft-07.
Keep OpenRPC document version, `info.version`, JSON-RPC protocol version, package
version, and metaschema asset release as distinct concepts.

**Call:** `DocumentVersion` has a 1.3.2 alternative and a 1.4 alternative with a
checked nonnegative patch number. Use canonical SemVer spellings without leading
zeroes, prerelease suffixes, or build metadata. The 1.4 upstream schema accepts
`^1\.4\.\d+$`; record its broader leading-zero acceptance as a discrepancy.
Other versions stay readable as JSON CST and produce `UnsupportedVersion` when
lowered to the supported document AST. Never upgrade a version during writing.

Freeze the 1.3.2 prose at spec commit
`df0df86da41d3a67b35a4b320067748344e035b5`. Keep Smithy's official meta-schema
release 1.14.9 and companion schemas unchanged. Freeze the 1.4 template and schema
at spec commit `876aa30e341f7669f5ba261e89520a5fc3057038`, rather than following
`master` or a live URL. The schema digest is
`a8a733cd87ef6ba2e1a38e6500090581b0f52b91051a0bad8386004366b11c56`.
Provenance and licenses belong beside the frozen assets.

### D2. Package boundaries and dependencies

**Call:** expose the document API from `moonrockz/openrpc`. Use subpackages
`json` for exact JSON values and syntax, `schema` for the draft-07 model and
schema-document checks, and `reference` for URI references, JSON Pointers, and
explicit resource lookup. Keep implementation-only helpers private. Publish one
module. No package imports Smithy, lander, notebooks, async, a UI, or a host API.

Share checked extension/domain values in a `domain` subpackage and re-export
their types from the root. Schema and document objects use the same Extensions
type. This avoids a schema-to-document import cycle and duplicate extension
models. Follow the existing repository type re-export pattern.

Use core JSON scalar string decoding and escaping, core collections, and core
big integers where appropriate. Reuse pinned test libraries already in this
workspace. No suitable URI or JSON Schema package was found among the current
dependencies. Implement the narrow standard contracts here, with conformance
tests, rather than importing configuration or Ion semantics. Do not add a new
third-party runtime dependency without recording its need and four-target proof.

The first story must compile a small independent consumer and inspect the
resolved dependency graph before these API boundaries become stable.

Proposed operation contracts, with final MoonBit syntax proved by the tracer:

| Operation | Explicit input | Result |
| --- | --- | --- |
| `json.parse` | Source String, optional source ID, limits | Owned CST or syntax/limit report |
| `read` | Source String, optional source ID, limits | CST, optional structurally decoded Document, SourceMap, diagnostics |
| `lower` | Existing CST, limits | Optional Document, SourceMap, diagnostics; no reference fetch or conformance claim |
| `validate` | Document, profile, ResourceSet, optional SourceMap, limits | ValidationReport only |
| `validate_closed` | Same explicit validation inputs | ValidationReport and optional ValidatedDocument |
| `schema.validate` | Schema, document pointer, base URI, ResourceSet, limits | Schema-document report |
| `schema.validate_json` | Untyped exact JSON and the same explicit validation inputs | Schema-document report, including malformed keyword forms |
| `write` | Document, format options, limits | JSON String or typed write/limit report |
| `reproduce` | CstDocument | Original String |
| `replace_value` | CstDocument, node ID from that parse, exact JSON Value, limits | Newly parsed read result or typed edit failure |

`read` never silently validates, resolves, or applies defaults. `write` can encode
a structurally valid AST that has document conformance errors. Callers that need
validation first use `validate_closed`; writing does not discard those findings.

### D3. Exact JSON and checked domain values

**Call:** an immutable JSON `Value` distinguishes null, boolean, string, array,
object, and `Number`. `Number::parse` accepts exactly the JSON numeric grammar.
Retain the complete number token. Derive sign, integer coefficient, and base-10
exponent for integer tests and comparisons without a binary float conversion.
Keep the exponent exact too. Resource limits may reject excessive input with a
typed limit finding; they must not round it or expand a huge power of ten.

Exact numeric equality treats `1`, `1.0`, and `1e0` alike and distinguishes
`9007199254740992` from `9007199254740993`. Lexical equality remains available.
Negative zero is retained on writing. Error codes are checked mathematical
integers, not host-sized integers. Validate names and component keys against
their specific field rules. Do not impose nonempty or ASCII restrictions on every
string just because a different field requires them.

Use private representations and checked constructors for `DocumentVersion`,
`MethodName`, `ComponentKey`, `ExtensionName`, `ErrorCode`, `JsonPointer`, and
`UriReference`. Return typed findings on failure. Public collections are
immutable views or defensive copies; constructor inputs cannot mutate a model.

Core `Json` interop is explicit. `from_core_json` captures the representation
that value still has and cannot recover discarded source digits. `to_core_json`
retains exact number tokens in `repr`; callers are warned that core arithmetic
and equality use its own semantics. Neither interop function is a source reader.

### D4. Full AST and source CST

**Call:** `Document` is a typed, structurally decoded AST. `ValidatedDocument`
adds a successful validation report, profile, version, and resource-snapshot
identity. A syntactically readable document is not automatically a valid one.
Leaf constructors check local invariants; document validation checks relationships.

Model every field of both supported versions. The inventory includes root
`$schema`, info, contact, license, external documentation, servers and variables,
methods, descriptors, tags, errors, links and link servers, examples, pairings,
all seven component categories, extensions, and reference alternatives at every
allowed site. Maintain an executable field inventory against frozen inputs.

The AST covers prose fields missing from the metaschema, such as example
`externalValue`, tag and pairing `summary`, and the historical component spelling
`examplePairingObjects`. Preserve `examplePairings` and `examplePairingObjects`
as distinct present wire tables with typed entries. Never rename one or redirect
a pointer silently. Version gates derive from the pinned sources, not the current
unversioned website. Keep absent versus explicit false, empty, and null distinct.
An absent method result and a result whose schema permits null are distinct.

Use `InlineOrReference[T]` for OpenRPC reference positions. `Schema` is a separate
boolean-or-object model, because draft-07 `$ref` siblings have different rules.
Examples and Error Object `data` contain exact instance values, not schemas.
Represent an example's inline value and external URL as distinct alternatives.
Conflicting fields remain inspectable in the CST and fail typed lowering.

Keep `Extensions` as checked `x-*` keys with arbitrary exact JSON values on each
extensible object and schema. Retain unknown ordinary fields in an explicit
additional-fields collection where the model admits them, and report their
conformance separately. Reference Objects are not extensible. Their extra
members remain in the CST, are ignored for reference semantics, and receive a
finding when a validation profile forbids them.

`CstDocument` owns the original String and an ordered JSON syntax tree with
object-member occurrences, punctuation, whitespace, raw scalar tokens, and spans.
It covers embedded schemas and extension payloads too. Duplicate decoded names,
including differently escaped spellings, survive parsing and fail AST lowering.
Strict JSON syntax excludes comments, trailing commas, multiple roots, and
JSON5/Ion forms. Lexically invalid input gives a syntax diagnostic; partial
error-recovery trees are outside this release.

AST source associations live in a separate `SourceMap` from structured document
paths to CST node IDs and key/value spans. Generated AST nodes have no source
location. CST IDs are scoped to one parse and are never promised stable after
edits. The first release supports unmodified CST reproduction and a checked
replacement of an existing value span. Replacement reparses and relowers a new
document. It does not promise arbitrary AST-to-CST synchronization, insertion,
deletion, or comment formatting.

### D5. Draft-07 is a first-class schema document

**Call:** model all draft-07 keyword forms, including boolean schemas, type sets,
numeric bounds, string constraints, tuple and single-schema items, object maps,
schema and property dependencies, composition, conditionals, annotations,
`$id`, `$schema`, `$ref`, `$comment`, formats, and content annotations. Preserve
unknown keywords as exact values. Names inside `properties`, `definitions`, and
other dictionaries are data keys, even when they look like keywords or `x-*`.

Typed schema construction checks keyword forms and local checked-value
invariants. It does not resolve references, compile regexes, or evaluate
instances. `validate_json` accepts exact JSON for reporting invalid schema
documents that cannot form a typed Schema. Typed views distinguish boolean,
object, reference, and unsupported-dialect schemas. Retained reference siblings
and foreign dialect contents remain explicit raw values.

Validate keyword value shapes and constraints against the official draft-07
metaschema contract. Walk only schema-bearing positions. Do not interpret
`default`, `examples`, `enum`, `const`, error data, or arbitrary extension values
as schemas. No default insertion or schema rewriting occurs.

An absent schema dialect means draft-07 in this API. Recognize the documented
HTTP/HTTPS draft-07 identifiers with and without the empty fragment as explicit
aliases. Other dialect declarations are preserved and report an unsupported
dialect. Never validate a 2020-12 schema as draft-07 and call it complete.
Unknown keywords stay legal under draft-07. A producer can retain later-dialect
keywords without this library claiming to interpret them.

Draft-07 `$ref` controls schema evaluation; retain siblings but do not treat them
as OpenRPC reference fields or apply them as assertions. `format`, content
encoding, and media type remain annotations for instance purposes. Validate the
types of pattern and format fields. The schema report explicitly distinguishes
structural schema checks from ECMA-262 regex compilation checks. A portable
regex grammar checker must validate the draft-07 ECMA-262 syntax used in
`pattern` and `patternProperties`; the existing regexp engine's smaller syntax
must not silently reject valid expressions. No regex matching or instance
validation is required.

Fix the syntax profile at ECMA-262 ninth edition, 2018, without flags, including
Annex B, with frozen Unicode 10.0.0 identifier properties. This makes the syntax
check independent of the host's JavaScript or regexp version. The qualification
corpus compares ordinary cases with pinned `@eslint-community/regexpp@4.12.2`;
exact quantifier arithmetic has additional tests beyond host floating-point
precision. `PatternError` offsets refer to decoded-pattern UTF-16 units, not
JSON source spans. Ship the Unicode data notice with the generated tables.

Schema validation accepts shared exact-value `Limits` plus explicit traversal,
reference, finding and enum comparison bounds. Default enum comparison work is
1,000,000 units, charged by both canonical UTF-16 lengths before equality. The
stricter explicit/shared finding limit applies. Unknown keywords remain legal
and do not make coverage incomplete.

Adapters can explicitly submit a schema held in an extension to the schema
validator, with its document pointer and base URI. The library does not know
Smithy extension names or scan arbitrary `schema` keys for hidden contracts.

### D6. References and explicit resolution

**Call:** preserve reference text and parse it into a URI-reference value with
fragment alternatives for a JSON Pointer and a draft-07 identifier fragment.
Use RFC 3986 relative resolution and RFC 6901 token escaping. URI percent decoding
and pointer `~0`/`~1` decoding occur at their specified layers, once each.
An empty pointer means the whole resource. Array indices use the RFC rules;
`-`, leading-zero indices, malformed escapes, and missing targets are failures.

Keep a general `UriReference` distinct from a JSON-target `Reference`. Metadata,
editor/dialect identifiers and external-example URLs can carry generic URI
fragments that are not JSON Pointers. Their constructors check RFC 3986 without
imposing JSON-target fragment rules. A JSON-target Reference exposes its checked
pointer or identifier alternative. Both retain original text. Change the
unpublished tracer's overloaded URL types before the first release.

Normalize identity separately from writing: fold scheme/host case, normalize
percent escapes and unreserved characters, and remove dot segments under the
RFC algorithm. Do not guess default ports or equate HTTP and HTTPS. Register
explicit aliases when required. An alias identifies the same owned resource;
it does not invent a second retrieval base. Relative references use the
resource's declared retrieval URI unless a schema identifier changes scope.

OpenRPC object references resolve relative to the owning resource URI. Schema
references use the nearest draft-07 `$id` scope, including nested identifiers.
An explicit `ResourceSet` supplies immutable URI-to-exact-JSON resources and an
optional root base URI. External resources may be complete OpenRPC documents,
schema documents, or fragments. Relative external references without a base URI
produce `MissingBaseUri`. Conflicting registered identifiers produce a finding.

Retrieval URIs are absolute and fragment-free; resource values can be extracted
JSON fragments. Declare schema roots explicitly in general JSON resources.
Typed Schema and Document helpers supply their known schema roots. Share the
draft-07 position rules across indexing and validation so arbitrary literal
values do not become schemas. The standalone initial-schema input and its
resolution root need not be the same value; preserve that distinction in graph
identity and source paths.

`read` preserves all references without resolving them. `validate` resolves local
references and reports unavailable external resources as incomplete checks.
`validate_closed` requires every relevant reference in the supplied resource set
to resolve with the expected target kind. Its successful result has no missing
reference checks. A caller never supplies an implicit network callback.

Keep graph edges instead of expanding references into trees. Recursive schemas
are valid; revisiting a schema node ends that traversal. OpenRPC reference-only
cycles with no concrete typed target produce `ReferenceCycle`. Wrong-kind
targets, broken pointers, and unavailable resources have distinct codes and
reference-chain locations. Never traverse `$ref` inside literal data. Server
URLs and example `externalValue` are retained values, not resource fetch requests.

### D7. Validation reports and upstream disagreements

**Call:** a report separates model shape, embedded-schema validity, reference
closure, normative rules, and pinned-metaschema compatibility. Each facet has
`Passed`, `Failed`, or `Incomplete`. No boolean success hides skipped work.

The default `Specification` profile checks normative requirements, including
unique method and parameter names, unique error codes, component-key grammar,
required names, server-variable constraints, link target existence, and parameter
ordering. A `MetaschemaCompatibility` profile supports existing producers that
pass the pinned artifact but differ from prose. Only differences enumerated in
the frozen discrepancy table can downgrade a normative error to a warning.
Initially these are optional-before-required parameter order and omitted server
or license names. Duplicate names/codes, missing link targets, wrong types,
unsupported dialects, malformed references, and all other normative failures
remain errors. Adding a downgrade changes public behavior and needs a spec change.
Compatibility does not claim strict conformance. A validated wrapper records the
profile used.

`validate` returns a report and no validated wrapper. It can report incomplete
reference coverage. `validate_closed` returns a report and an optional
`ValidatedDocument`. Under Specification, model shape, schema documents,
reference closure, and normative rules must all pass. A pinned-artifact failure
does not block that wrapper, but stays in the report. Under
MetaschemaCompatibility, model shape, schema documents, reference closure, and
pinned-artifact compatibility must pass, and normative rules must have no errors
outside the explicit downgrade list. Neither operation creates a wrapper when a
required facet is failed or incomplete, including findings truncated by limits.
Thus a prose-valid external example can qualify under Specification and fail
under MetaschemaCompatibility. Both results are intentional and testable.

Implement pinned-artifact checks as versioned built-in structural rules whose
inventory is checked against the frozen schemas. The independent Ajv suite
checks those results; it is not a runtime library dependency. This does not
require a general JSON Schema instance evaluator in the published module.

Maintain a bounded discrepancy table. In particular, the 1.3.2 prose requires
optional parameters after required ones. Smithy deliberately supports optional
interior positional parameters. Both profiles preserve the exact descriptor
order; the default emits an error and compatibility emits a warning. No sorting
or inserted null value repairs it. Artifact omissions such as prose-only fields,
server/license required names, example `externalValue`, and component-table
spelling are independent facet results, never hidden exceptions in the reader.

The document library does not validate example instances against schemas. Its
report marks that operation outside its contract. Smithy's existing runtime
validator remains responsible for example and protocol agreement.

`Diagnostic` carries a stable typed code, severity, phase, version/profile,
structured document pointer, message, optional source ID/span, related locations,
and a structured reference chain. Missing fields point to the parent with an
expected-field detail. Duplicate findings include both occurrences. No ShapeId
or host path is required. Smithy can map pointers to shape-linked warnings later.
Order diagnostics by resource URI, pointer tokens, code, and source occurrence.

Spans use half-open UTF-16 code-unit offsets matching MoonBit String indexing.
Line and column views are one-based, with columns in the same code units and
CRLF treated as one newline. Test non-BMP characters and escaped member names
on every target. Messages may improve without changing typed codes.

### D8. Reproduction, canonical writing, and limits

**Call:** `reproduce(cst)` returns exactly the original String, including leading
and trailing whitespace, CRLF, key order, escape spelling, and numeric spelling.
It works for valid JSON that is invalid OpenRPC. It does not promise original
file encoding or BOM bytes. The library accepts text; byte decoding belongs to
the caller. UTF-8 encoding of reproduced valid text is stable when no byte-level
decoding information was discarded by the caller.

`write(document)` is deterministic canonical formatting for this library. Use
compact JSON, no final newline, object keys sorted by decoded UTF-16 code units,
minimal JSON string escaping, and the stored exact numeric token. Preserve every
array order, present field, unknown retained value, and reference spelling.
Do not sort methods or parameters, normalize schema values, insert defaults,
fetch examples, or change versions. Equal exact AST representations produce
equal output on all targets. Numerically equal tokens need not have equal bytes.
This is not RFC 8785/JCS numeric canonicalization or a signing format.

Provide pretty formatting as an explicit writer option. Parse/write/parse must
preserve the AST's present fields and exact values. Write/read/write must be
idempotent with the same options. A checked CST value replacement preserves all
source outside the replaced span and returns a new source map.

Use iterative traversal or explicit stacks for syntax, lowering, writing, schema
walks, and reference graphs. Public `Limits` has finite defaults for source size,
nesting, nodes, number-token size, reference edges, and findings. Supply an
explicit unlimited mode where the implementation can remain stack safe.
Limit findings name the operation and bound. Truncating diagnostics marks the
report incomplete. Large exponents must not cause unbounded decimal expansion.
The tracer fixes the JSON defaults at 8,388,608 UTF-16 code units of source or
output, 100,000 value nodes, 256 open containers, 4,096 UTF-16 code units per
number token, and 256 lowering findings. Schema graph checks default to 10,000
visited nodes, 4,096 reference edges and 256 findings. Later operations use these
same bounds where they apply and document any additional limits.

### D9. Qualification and rollout

**Call:** the first story proves a thin end-to-end path for both version lines,
exact numeric retention, CST reproduction, extension retention, one local schema
reference, structured diagnostics, and an independent four-target consumer.
Do not label that subset a release candidate.

Expand each capability with its acceptance tests and runnable docs. An
unpublished qualification suite compares documents with pinned official assets
using independent Ajv. Freeze the draft-07 metaschema too. Keep a discrepancy
corpus with separate expected normative and artifact outcomes. Independent
JavaScript validation does not prove exact large-number semantics; prove those
with exact token/value laws in MoonBit on all targets.

Adapt the existing MoonBit isolated-registry task pattern, not shell automation.
Package dry runs and a loopback registry consumer prove package contents and
dependency isolation. A public-registry consumer outside `moon.work`, with no
override or local cache substitution, separately proves the approved published
version. Record candidate source SHA, archive SHA-256, exact dependency version,
target results, dependency graph, and the commands used.

Track release approval and public proof separately from building the candidate.
After publication approval and upload, public-consumer proof gates the Smithy
migration. Create a separate Smithy workspace from the documented baseline.
Preserve `convert_result -> Conversion { document : Json, warnings }`,
`convert -> Json`, shape-linked errors, and adapter loss policies deliberately.
Use the exact published dependency. Re-run its existing feature, unit, plugin,
isolated-consumer, official-schema, reference, determinism, failure-status, and
runtime-agreement qualification. Keep the active evidence checkout unchanged.

## Risks / trade-offs

- Upstream prose and assets disagree. Separate validation facets and freeze a
  discrepancy corpus. Do not pick a live upstream revision to make a test pass.
- A full typed draft-07 model and portable regex syntax checker are substantial.
  Give each a tracked deliverable and reject incomplete release qualification.
- An independent exact JSON syntax layer adds code. Reuse core scalar string
  handling and escaping, and test source/value laws against independent parsers.
- Compatibility validation can look like strict conformance. Store the profile
  in reports and validated values, and keep normative warnings visible.
- Package checks can accidentally resolve workspace members. Run consumers in
  isolated directories and audit both resolution and archive identities.

## Migration and rollback

The new library does not alter current lander or notebook consumers. Before
publication, any API change stays within this proposal and candidate. After
publication, use normal versioned compatibility changes. Smithy's migration is
a separate change and can revert its adapter commit while retaining the existing
qualified implementation. Never overwrite an already published artifact.
