# OpenRPC documents

`moonrockz/openrpc` is a developing portable reader, writer and document
validator. It contains the complete typed OpenRPC `1.3.2`/`1.4.x` model and
draft-07 keyword model, exact JSON values, a source-preserving CST and
reference resolution over explicit resources. Full document validation, source
editing and release qualification remain tracked work. This development module
is not a release candidate.

Reading keeps both the original JSON source and a typed document when structural
decoding succeeds. Writing retains exact numeric tokens, extensions, absent
fields and array order. Object keys sort by UTF-16 code units. Canonical writing
does not insert defaults or change the document version.

The examples import the root as `@openrpc`, exact JSON as `@exact`, schemas as
`@schema`, and references as `@reference`.

```mbt check
///|
test {
  let source = " {\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"service-9\"},\"methods\":[],\"x-number\":9007199254740993} "
  let result = @openrpc.read(source)
  assert_eq(result.cst().unwrap().reproduce(), source)
  let document = result.document().unwrap()
  assert_eq(document.info().version(), "service-9")
  assert_eq(
    @openrpc.write(document).unwrap(),
    "{\"info\":{\"title\":\"API\",\"version\":\"service-9\"},\"methods\":[],\"openrpc\":\"1.4.0\",\"x-number\":9007199254740993}",
  )
}
```

The public `json` package provides immutable exact JSON values and an owned CST.
Its node spans use half-open UTF-16 offsets. Nodes retain member occurrences and
decoded keys; the owned source retains punctuation, whitespace and raw spelling.
Duplicate decoded keys preserve the CST but fail semantic lowering. The parser,
lowering and writer use explicit stacks.

Default JSON limits are 8,388,608 UTF-16 code units of source/output, 100,000
nodes, 256 open containers, 4,096 code units per number and 256 lowering
findings. `json.Limits::new`
accepts explicit bounds. Source size is a text bound, not a UTF-8 byte bound.
Large decimal exponents are kept exact without expanding powers of ten.

`CstDocument.tokens()` partitions the original text into tokens and whitespace.
Each token has its original text and span. `source_map()` maps decoded paths to
all value occurrences, including duplicate members. A location separates the
member-name span from the value span. Positions use one-based lines and UTF-16
columns; CRLF counts as one line break. Each location's node index belongs to
the owning CST and is not stable across parses or edits. Generated AST values
have no source map.

```mbt check
///|
test {
  let cst = @exact.parse("{\"n\":9007199254740993}", source_id=Some("api.json")).unwrap()
  let location = cst.source_map().locations(["n"])[0]
  assert_eq(location.source_id(), Some("api.json"))
  assert_eq(cst.slice(location.value_span()).unwrap(), "9007199254740993")
  assert_eq(cst.slice(location.key_span().unwrap()).unwrap(), "\"n\"")
}
```

Exact `Value.equals` compares object members without regard to their order and
retains numeric token distinctions. Select `numeric=true` for mathematical
numeric equality. `Number.numeric_compare` orders exact decimals and exponents.
Neither operation converts numbers to binary floating point. Equality returns
`Result[Bool, Diagnostic]` and reports exhaustion through `LimitExceeded`.
It bounds visited and queued node pairs, depth, number tokens, and aggregate
key/string/number text on each operand. It never treats exhaustion as inequality.

Core `Json` interop is explicit. `from_core_json` uses a present numeric `repr`
after checking its syntax; without `repr`, it captures the current finite
Double representation. It cannot recover source digits that the caller lost.
`to_core_json` always sets exact numeric `repr`. Core arithmetic and equality
still use Double semantics. Both conversions copy collections and enforce the
JSON limits. `Limits.unlimited()` removes policy bounds within the maximum
representable String/Array sizes; available host memory is still finite.

```mbt check
///|
test {
  let exact = @exact.parse("9007199254740993").unwrap().lower().unwrap()
  let core = @exact.to_core_json(exact).unwrap()
  assert_true(@exact.from_core_json(core).unwrap().equals(exact).unwrap())
  let code = @openrpc.ErrorCode::parse("-90071992547409931234567890").unwrap()
  assert_eq(code.number().token(), "-90071992547409931234567890")
  let extensions = @openrpc.Extensions::from_json(
    @exact.parse("{\"x-value\":false}").unwrap().lower().unwrap(),
  ).unwrap()
  assert_true(
    extensions.get(@openrpc.ExtensionName::parse("x-value").unwrap()) is Some(_),
  )
}
```

`ComponentKey`, `ExtensionName`, and `ErrorCode` have checked constructors.
Component keys follow the OpenRPC component grammar. Extension names begin with
lowercase `x-` and retain arbitrary exact values. Error codes are mathematical
integers with no machine-integer restriction. Each field keeps its own rules;
these constructors do not impose a common string restriction on unrelated fields.

Validation returns separate model, schema-document, reference, normative and
pinned-artifact coverage results. `Specification` is the default profile.
`MetaschemaCompatibility` reports the documented optional-before-required
parameter-order discrepancy as a warning. It does not reorder descriptors.
Duplicate names remain errors in both profiles.

```mbt check
///|
test {
  let document = @openrpc.read(
      "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[]}",
    )
    .document()
    .unwrap()
  let result = @openrpc.validate_closed(document)
  assert_true(result.document() is Some(_))
  assert_eq(result.report().references(), @openrpc.Passed)
  assert_eq(result.report().artifact(), @openrpc.Passed)
}
```

The artifact facet checks the document's own JSON against its version's pinned
metaschema. A closed Specification result requires the model, schema, reference
and normative facets to pass. A closed compatibility result also requires
artifact compatibility. Neither profile conceals failed or incomplete required checks.

References never trigger network or filesystem access. Validation resolves
references only through an explicit `@reference.ResourceSet` and an optional
document `base` URI. Each OpenRPC reference site (methods, parameters, results,
errors, links, tags, example pairings and their examples) follows its
reference-only chain. Each reference resolves against the resource that holds
it, and the target is decoded with that kind's checked decoder. A target that
does not decode is `WrongType` at the referencing site. A chain that revisits a
location is `ReferenceCycle`. Schema references use draft-07 `$id` scopes and
recursive schema graphs are valid. Server URL templates, example
`externalValue`, error data, example values and `x-*` payloads are never
resolved, even when they contain `$ref`.

```mbt check
///|
test {
  let document = @openrpc.read(
      "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[{\"$ref\":\"shared.json#/methods/ping\"}]}",
    )
    .document()
    .unwrap()
  let base = @reference.UriReference::parse("https://api.example/openrpc.json").unwrap()
  // Without the shared resource the reference is unresolved, not failed.
  let open = @openrpc.validate(document, base=Some(base))
  assert_eq(open.references(), @openrpc.Incomplete)
  assert_true(
    @openrpc.validate_closed(document, base=Some(base)).document() is None,
  )
  // Supplying it, under an alias, closes the check. Nothing is fetched.
  let shared = @reference.Resource::new(
    @reference.UriReference::parse("https://cdn.example/v1/shared.json").unwrap(),
    @exact.parse(
      "{\"methods\":{\"ping\":{\"name\":\"ping\",\"params\":[],\"result\":{\"name\":\"pong\",\"schema\":{\"$ref\":\"#/definitions/Pong\"}}}},\"definitions\":{\"Pong\":{\"type\":\"string\"}}}",
    )
    .unwrap()
    .lower()
    .unwrap(),
    aliases=[
      @reference.UriReference::parse("https://api.example/shared.json").unwrap(),
    ],
    schema_roots=[@reference.JsonPointer::parse("/definitions/Pong").unwrap()],
  ).unwrap()
  let resources = @reference.ResourceSet::new([shared]).unwrap()
  let closed = @openrpc.validate_closed(document, resources~, base=Some(base))
  assert_eq(closed.report().references(), @openrpc.Passed)
  assert_true(closed.document() is Some(_))
}
```

`Document::as_resource` registers a document with every schema position in its
typed model declared as a schema root, so other documents can reference it.
When `base` names a registered resource that holds exactly the validated
document, that resource is used. Without `base`, relative external references
report `MissingBaseUri` and leave reference coverage incomplete; a relative
schema `$id` still scopes the fragment-only references inside it. Findings for targets in another resource carry pointers
relative to that resource. Chains are bounded by `max_depth`, and schema graphs
by their node, edge and finding bounds. Schema graph defaults
are 10,000 visited nodes, 4,096 reference edges and 256 findings per check.

Schema-document validation checks schema keyword forms and references. It does
not apply schemas to payload or example instances. Error data and arbitrary
`x-*` payloads remain instance values. JSON-RPC envelopes, notifications, batches
and exchanges require a separate runtime validator.

The [draft-07 model guide](schema/README.mbt.md) covers the complete typed keyword
model, checked exact bounds, tuple items, dependencies and literal-data boundaries.
`Schema.from_json` now checks typed forms. Use `schema.validate_json` to report
malformed untyped schema documents. Complete conformance and reference-resource
checks remain tracked work.

The document API covers metadata, servers and variables, methods, descriptors,
tags, links, errors, examples, pairings and all component tables. Each object
offers checked `new`/`from_json` construction, typed accessors, `to_json`, shared
`extensions`, and explicit `additional_fields`. Public arrays and maps are
defensive copies. Generated values have no source locations.

```mbt check
///|
test {
  let null_schema = @schema.Schema::from_keywords([
    @schema.Type(@schema.TypeConstraint::one(@schema.NullType)),
  ]).unwrap()
  let result = @openrpc.ContentDescriptor::new(
    "result",
    null_schema,
    required=Some(true),
  ).unwrap()
  let op = @openrpc.Method::new(
    @openrpc.MethodName::parse("ping").unwrap(),
    [],
    result=Some(@openrpc.Inline(result)),
    param_structure=Some(@openrpc.ByName),
  ).unwrap()
  let document = @openrpc.Document::new(
    @openrpc.DocumentVersion::parse("1.3.2").unwrap(),
    @openrpc.Info::new("Example API", "service-v9").unwrap(),
    [@openrpc.Inline(op)],
  ).unwrap()
  assert_eq(document.info().version(), "service-v9")
  assert_true(@openrpc.write(document).unwrap().contains("\"type\":\"null\""))
  let notification = @openrpc.Method::new(
    @openrpc.MethodName::parse("notify").unwrap(),
    [],
  ).unwrap()
  assert_true(notification.result() is None)
}
```

An absent method result describes a notification. A present result whose schema
permits null describes a successful null result. Optional flags and collections
retain explicit false, empty arrays/maps and absence. Server URL templates and
link parameters are retained data and are never executed.

```mbt check
///|
test {
  let schema = @schema.Schema::from_keywords([
    @schema.Type(@schema.TypeConstraint::one(@schema.StringType)),
  ]).unwrap()
  let components = @openrpc.Components::new(
    schemas=Some([(@openrpc.ComponentKey::parse("Text").unwrap(), schema)]),
  ).unwrap()
  let descriptor = @openrpc.ContentDescriptor::new(
    "text",
    @schema.Schema::from_json(
      @exact.parse("{\"$ref\":\"#/components/schemas/Text\"}")
      .unwrap()
      .lower()
      .unwrap(),
    ).unwrap(),
  ).unwrap()
  assert_eq(components.schemas().unwrap()[0].0.to_string(), "Text")
  assert_true(descriptor.schema().kind() is @schema.ReferenceSchema(_))
  let name = @openrpc.ExtensionName::parse("x-contract").unwrap()
  let extensions = @openrpc.Extensions::from_entries([(name, schema.to_json())]).unwrap()
  let submitted = @schema.Schema::from_json(extensions.get(name).unwrap()).unwrap()
  assert_true(
    @schema.validate(submitted, root=submitted.to_json())
    .diagnostics()
    .is_empty(),
  )
}
```

Extensions keep arbitrary exact values. A caller can explicitly submit an
extension-held schema for schema-document checks. The library does not infer
schemas from extension names or object keys.

```mbt check
///|
test {
  let error = @openrpc.ErrorObject::new(
    @openrpc.ErrorCode::parse("-90071992547409931234567890").unwrap(),
    "Failed",
    data=Some(
      @exact.parse("{\"$ref\":\"literal\",\"schema\":17}")
      .unwrap()
      .lower()
      .unwrap(),
    ),
  ).unwrap()
  let external = @openrpc.Example::new(
    @openrpc.ExternalExample(
      @reference.UriReference::parse("https://example.invalid/value").unwrap(),
    ),
  ).unwrap()
  let components = @openrpc.Components::new(
    errors=Some([(@openrpc.ComponentKey::parse("E").unwrap(), error)]),
    examples=Some([
      (@openrpc.ComponentKey::parse("External").unwrap(), external),
    ]),
    example_pairings=Some([]),
    example_pairing_objects=Some([]),
  ).unwrap()
  assert_true(components.to_json().get("examplePairings") is Some(_))
  assert_true(components.to_json().get("examplePairingObjects") is Some(_))
  assert_true(components.errors().unwrap()[0].1.data() is Some(_))
}
```

The two pairing table spellings remain distinct; pointers are never redirected.
Example payloads distinguish absent, literal and external values. Error data is
an instance value. Names whose requirements differ by version or profile retain
their presence so conformance checks can report the applicable rule.

Run `mise run check:openrpc-assets` for the frozen asset checks and
`mise run check:openrpc` for module tests, official inventories and the four-target public consumer
comparison. No publication has occurred.
