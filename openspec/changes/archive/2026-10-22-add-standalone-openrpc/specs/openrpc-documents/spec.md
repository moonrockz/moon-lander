## ADDED Requirements

### Requirement: Independent versioned OpenRPC module

The workspace SHALL provide `moonrockz/openrpc` under `pkgs/openrpc`. Its public
library SHALL support OpenRPC 1.3.2 and the 1.4.x compatibility line on native,
wasm, js, and wasm-gc. It MUST keep document, service, protocol, package, and
metaschema versions distinct. Its dependency graph MUST exclude Smithy, lander,
notebooks, UI, and host runtime packages.

#### Scenario: Both supported versions retain their identity

- **WHEN** a consumer reads and writes documents with `openrpc` values `1.3.2`,
  `1.4.0`, and `1.4.12`, each with `info.version` equal to `2026-10-21`
- **THEN** all documents retain both version fields unchanged on all four targets
- **AND** the consumer needs no Smithy or application framework import

#### Scenario: Unsupported or malformed versions remain inspectable

- **WHEN** valid JSON has `openrpc` equal to `2.0.0`, `1.2.6`, or `1.4.01`
- **THEN** the CST retains its source and typed lowering reports an unsupported
  or malformed version without changing it

### Requirement: Checked immutable domain values and exact JSON numbers

The library SHALL use checked domain types for versions, field-specific names,
extension names, component keys, integer error codes, pointers, and URI references.
It SHALL preserve arbitrary valid JSON number tokens without binary float
rounding. Public models MUST resist mutation through retained collection inputs
or returned collection values.

#### Scenario: Exact numeric tokens survive every document location

- **WHEN** schemas, examples, error data, and extensions contain
  `9007199254740993`, `0.10000000000000000001`, `1e400`, and `-0.00`
- **THEN** reading and writing retain every token on all four targets
- **AND** exact comparison distinguishes adjacent large integers and treats
  `1`, `1.0`, and `1e0` as the same numeric value

#### Scenario: Invalid construction does not create a valid domain value

- **WHEN** a caller constructs a number from `01`, an error code from `1.5`,
  an extension name from `vendor-data`, or a pointer from `/bad~2escape`
- **THEN** construction fails with a typed diagnostic

#### Scenario: Mutable inputs do not change a document

- **WHEN** a caller changes a collection supplied to an AST constructor, or a
  mutable copy returned by an accessor
- **THEN** the original document and its writer output do not change

### Requirement: Complete typed document AST

The AST SHALL cover every field defined by the pinned supported specification
sources, including fields omitted from the metaschemas. It SHALL represent every
allowed inline/reference alternative, every component category, embedded
schemas, extensible objects, and presence distinctions without source spans
being required. AST decoding and document validation MUST be distinct operations.

#### Scenario: Full model is available without Smithy

- **WHEN** a consumer constructs a document with contact and license metadata,
  external docs, server variables, method servers, tags, links with params and a
  server, examples and pairings, and all seven component categories
- **THEN** each field has a typed accessor and survives write/read
- **AND** every permitted reference position has a typed reference alternative

#### Scenario: Source prose fields omitted by an artifact are retained

- **WHEN** a supported document uses a prose-defined tag or pairing summary,
  external example, or historical `examplePairingObjects` table
- **THEN** the AST retains the field and wire spelling
- **AND** its normative and artifact validation outcomes remain distinguishable

#### Scenario: Presence is not replaced by defaults

- **WHEN** documents differ by an absent boolean versus explicit false, an absent
  collection versus an empty collection, or absent result versus a null result schema
- **THEN** the AST and writer retain each distinction and insert no defaults

### Requirement: Strict JSON source-preserving CST

The reader SHALL parse strict JSON into a CST that owns the original text and
retains ordered member occurrences, raw tokens, punctuation, trivia, and spans
throughout the document. Source reproduction MUST return exactly the same String
for every successfully parsed CST, including JSON that fails OpenRPC validation.
AST lowering MUST reject duplicate decoded object names without discarding the CST.

#### Scenario: Source text survives without formatting changes

- **WHEN** input includes CRLF, leading and trailing whitespace, unusual member
  order, `\u` string escapes, and non-normalized numeric spellings
- **THEN** CST reproduction equals the original text exactly
- **AND** embedded schemas and extension payloads have navigable CST nodes

#### Scenario: Duplicate occurrences remain visible

- **WHEN** an object contains keys `name` and `\u006eame`
- **THEN** the CST retains both occurrences and lowering reports their duplicate
  decoded name with both source locations

#### Scenario: Non-JSON syntax fails explicitly

- **WHEN** input contains a comment, trailing comma, Ion annotation, invalid
  scalar token, or second root value
- **THEN** the reader returns a syntax diagnostic at the offending source span

### Requirement: Explicit AST and CST relationships

The reader SHALL provide a source map from structured document paths to CST nodes
and source spans. The library SHALL support a checked replacement of an existing
CST value span that returns a new parsed document and source map. It MUST preserve
all source outside that span and MUST reject stale or mismatched node identities.

#### Scenario: A source edit preserves surrounding source

- **WHEN** a caller replaces one extension value in a parsed document
- **THEN** the new document contains the replacement and all text outside the
  original value span is unchanged
- **AND** new AST diagnostics use the new source map

#### Scenario: A generated model has no invented source

- **WHEN** a caller validates an AST constructed without reading text
- **THEN** diagnostics carry document pointers and omit source spans

### Requirement: Full draft-07 schema-document handling

The library SHALL model boolean schemas and all draft-07 keyword alternatives.
It SHALL check schema-document keyword forms, numeric constraints, and ECMA-262
regex syntax without applying schemas to runtime instances. It MUST retain
unknown keywords, annotations, and exact instance-valued keyword contents.
Unsupported declared dialects MUST prevent a complete schema-validation result.

#### Scenario: Schema forms and annotations remain intact

- **WHEN** schemas use boolean forms, tuple items, type arrays, definitions,
  dependencies, composition, conditionals, formats, content annotations, and
  unknown keywords
- **THEN** all forms survive read/write and draft-07 checks follow their keyword
  contracts without inserting defaults or stripping annotations

#### Scenario: Invalid keyword and regex forms are diagnosed

- **WHEN** a schema contains `multipleOf: 0`, `required: [1]`, empty `allOf`,
  or an invalid ECMA-262 expression in `patternProperties`
- **THEN** schema validation reports the relevant keyword pointer and code
- **AND** a valid ECMA-262 construct outside the existing MoonBit regexp engine's
  matching subset is not rejected merely because that engine cannot execute it

#### Scenario: Literal data is not walked as a schema

- **WHEN** a schema has properties named `examples`, `default`, or `x-vendor`,
  and literal values under `default`, `const`, `enum`, or `examples` contain `$ref`
- **THEN** the property schemas are checked and their references are visited
- **AND** the literal `$ref` values are preserved without reference resolution

#### Scenario: A different declared dialect is not silently reinterpreted

- **WHEN** an embedded schema declares the 2020-12 dialect
- **THEN** its data remains intact and the schema report identifies unsupported
  dialect coverage instead of returning a complete draft-07 success

### Requirement: Pure typed reference resolution

The library SHALL distinguish OpenRPC object references from schema references.
It SHALL resolve RFC 3986 URI references and RFC 6901 pointers against an explicit
immutable resource set, using nested draft-07 identifier scopes where applicable.
It MUST perform no network, filesystem, or document-controlled code execution.
Reading MUST preserve references without requiring resolution.

#### Scenario: Escaped local targets and recursive schemas resolve

- **WHEN** schema references use valid escaped pointer tokens and a recursive
  component graph
- **THEN** closed validation resolves every edge without expanding the graph
  into an infinite tree or rejecting valid schema recursion

#### Scenario: External resources require explicit inputs

- **WHEN** a reference targets an unavailable external resource
- **THEN** open validation reports incomplete reference coverage and closed
  validation fails, with no fetch attempt
- **AND** supplying that resource and any required base URI permits resolution

#### Scenario: Schema identifiers change relative scope

- **WHEN** nested schema `$id` values change the base for a relative `$ref`
- **THEN** resolution uses the nearest scope and the explicit resource set
- **AND** duplicate identifiers, missing bases, malformed pointers, wrong-kind
  targets, and reference-only cycles have distinct diagnostics

### Requirement: Extensions and instance data are lossless

The library SHALL retain arbitrary exact JSON under `x-*` at every extensible
site. Error Object `data` and example values MUST remain instance data. It SHALL
allow callers to submit extension-held schemas explicitly with their base and
document path. It MUST NOT implement producer-specific preserve/omit/fail policies.

#### Scenario: Producer metadata survives without producer imports

- **WHEN** a document contains `x-smithy-protocol`, `x-smithy-error-data`,
  `x-smithy-error-examples`, and `x-smithy-param-structure`
- **THEN** the reader and writer retain their complete values without Smithy imports
- **AND** an adapter can explicitly validate a schema in the error-data extension

#### Scenario: A literal reference in error data is not resolved

- **WHEN** Error Object `data` or an arbitrary extension contains
  `{"$ref":"https://example.invalid/instance"}`
- **THEN** it remains unchanged and does not add a resource requirement

### Requirement: Structured validation with explicit coverage

Validation SHALL separate model shape, schema documents, reference closure,
normative rules, and pinned-artifact compatibility. Each facet SHALL report
passed, failed, or incomplete. Specification SHALL enforce normative rules.
MetaschemaCompatibility SHALL downgrade only listed discrepancies to warnings.
Reports and validated values MUST identify the profile. No profile may repair input.

#### Scenario: Optional interior parameters have explicit profile results

- **WHEN** an optional parameter precedes a required parameter
- **THEN** Specification validation reports a normative error and
  MetaschemaCompatibility reports the same discrepancy as a warning
- **AND** both preserve the original parameter order and all required flags

#### Scenario: Semantic document constraints are checked

- **WHEN** resolved methods duplicate names, params duplicate names, errors
  duplicate exact integer codes, or a link names a missing method
- **THEN** document validation identifies each failed semantic constraint

#### Scenario: Findings remain useful across targets and source origins

- **WHEN** the same invalid document is checked on each target with a non-BMP
  character before an offending field
- **THEN** codes, severity, phase, structured pointers, related locations,
  reference chains, and deterministic finding order agree
- **AND** half-open UTF-16 source offsets and one-based line/column views agree

### Requirement: Profile-gated closed validation

`validate` SHALL return only a report. `validate_closed` SHALL produce a validated
wrapper only when model, schema-document, and reference facets pass.
Specification SHALL also require normative success. MetaschemaCompatibility
SHALL require artifact success and no normative errors outside its downgrade
list. Failed or incomplete required checks MUST prevent a validated wrapper.

#### Scenario: Profile success does not hide artifact disagreement

- **WHEN** a prose-valid external example fails the pinned artifact's required
  inline-value rule and all references are closed
- **THEN** Specification can return a validated wrapper with the artifact failure
  retained in its report, and MetaschemaCompatibility cannot return a wrapper

#### Scenario: Compatibility cannot excuse unrelated semantic errors

- **WHEN** a document has duplicate resolved method names or error codes
- **THEN** both profiles report errors and neither closed check returns a wrapper

#### Scenario: Open resource coverage is not a closed validation proof

- **WHEN** an unavailable external resource leaves reference checks incomplete
- **THEN** the report states incomplete coverage and no validated wrapper exists

### Requirement: Deterministic canonical writing

The writer SHALL sort object keys by decoded UTF-16 code units, retain array
order and exact number tokens, use compact JSON without a final newline by
default, and expose pretty formatting explicitly. It MUST preserve present
fields, retained extras, references, and extensions without inserting defaults.
Its documentation MUST distinguish this policy from source reproduction and JCS.

#### Scenario: Canonical output is stable and preserves meaning

- **WHEN** a supported AST is written and read repeatedly on all four targets
- **THEN** write/read/write is byte-stable for the same options and the AST retains
  every exact value and presence distinction
- **AND** method, descriptor, example, and schema-array orders remain unchanged

### Requirement: Bounded stack-safe processing and clear runtime boundary

Public operations SHALL expose documented resource limits and typed exhaustion
diagnostics. They MUST avoid uncontrolled call-stack recursion. Truncated checks
MUST be marked incomplete. The library MUST document that schema-document and
OpenRPC validation do not validate JSON-RPC envelopes, examples as instances,
notifications, batches, IDs, or exchanges.

#### Scenario: Exhaustion does not masquerade as validation success

- **WHEN** explicit nesting, node, numeric-token, reference-edge, or finding limits
  are exhausted
- **THEN** processing returns a typed finding naming the exhausted operation
- **AND** partial validation is incomplete, with no rounded number or stack crash

#### Scenario: A document cannot prove runtime exchange validity

- **WHEN** a caller validates an OpenRPC document with a null result schema
- **THEN** the result makes no notification-only, response-correlation, or
  envelope-validation claim
