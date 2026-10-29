# Moon-Lander language

## Actors (proposed)

**Actor**:
A unit that owns private state and one mailbox and handles one message at a
time. It is like a lightweight BEAM process, but it is cooperative and shares
memory with other actors. It is not an operating-system process.

**Receive**:
An immutable description of what an actor takes from its mailbox next and of
its final result. Only the runtime and the test runner run it; no other code
takes messages from a mailbox.

**Actor context**:
What an actor's receives can use: its own reference, its child scope and its
queue length. It cannot take messages, so it is safe to pass to other tasks.

**Actor name**:
A reusable label reserved within an actor's owner scope. Separate scopes can
have actors with the same label, which a combined directory must distinguish.

**Actor address**:
The immutable local identity of one actor lifetime. A replacement actor has a
different address even when it reuses the same name.

**Actor reference**:
A typed send capability for one actor lifetime. It remains bound to that actor
after the actor stops and never redirects to a replacement.

**Actor directory**:
An immutable collection of references to actors with one message protocol.
Membership is specific to actor lifetimes and does not give ownership of them.

**Directory composition**:
Set union of directory members by actor address. Adding the same actor more
than once does not create another member.

**Directory removal**:
Excluding a specific actor lifetime from a new directory value. It does not
stop the actor or revoke references that other components hold.

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
