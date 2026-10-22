# Moon-Lander language

## OpenRPC

**OpenRPC document version**:
The specification version named by a document's `openrpc` field. It is distinct
from the service version, protocol version, and metaschema release.
_Avoid_: OpenRPC package version

**Service version**:
The producer's version string carried by `info.version`. Smithy derives it from
the selected service unless its adapter configuration overrides it.

**Metaschema release**:
A release of an upstream artifact used to check OpenRPC document structure.
Its release number is independent of the document versions that it accepts.

**Document conformance**:
Agreement of an OpenRPC description with a named specification and validation
profile. It does not establish the validity of runtime JSON-RPC exchanges.

**Schema-document validation**:
Checking that an embedded JSON Schema has the keyword forms and reference
structure required by its declared dialect.
_Avoid_: runtime validation

**URI reference**:
A general resource identifier that can be absolute or relative and can carry a
fragment. A URL fragment does not necessarily identify a JSON value.

**JSON reference**:
A URI reference used to identify a JSON target through a pointer or a named
schema identifier.

**Resource snapshot**:
An explicit collection of fixed resource values and their identifiers. It does
not imply permission to retrieve missing resources.

**Retrieval URI**:
The declared URI of a resource as supplied to the library. It establishes a
base for relative references unless a schema identifier changes that base.

**Schema root**:
A value explicitly identified as a schema, from which schema-specific child
positions and identifier scopes can be interpreted.

**Source reproduction**:
Returning the same source text that was read, including whitespace, member order,
escapes, and numeric spellings.
_Avoid_: canonical writing

**Canonical writing**:
Producing deterministic JSON formatting from a document model under a documented
ordering and spelling policy.
_Avoid_: source reproduction
