# Draft-07 schema documents

`moonrockz/openrpc/schema` models all 46 draft-07 keywords. It keeps exact JSON
and exposes typed views for boolean schemas, object schemas, references and
unsupported dialect declarations. Construction checks keyword forms and local
invariants. Document validation checks references and conformance separately.
This package does not evaluate payload or example instances.

```mbt check
///|
test {
  let types = @schema.TypeConstraint::many([
    @schema.StringType,
    @schema.NullType,
  ]).unwrap()
  let schema = @schema.Schema::from_keywords([
    @schema.Type(types),
    @schema.MaxLength(
      @schema.NonNegativeInteger::parse("9007199254740993").unwrap(),
    ),
    @schema.Default(@json.Value::null()),
    @schema.ReadOnly(false),
  ]).unwrap()
  guard schema.kind() is @schema.ObjectSchema(object) else { fail("object") }
  guard object.keyword("maxLength").unwrap() is @schema.MaxLength(bound) else {
    fail("bound")
  }
  assert_eq(bound.number().token(), "9007199254740993")
  assert_true(schema.to_json().get("default") is Some(_))
  assert_true(object.keyword("minLength") is None)
}
```

`Items` distinguishes a single schema from tuple schemas. `Dependency`
distinguishes a schema dependency from a property-name list. Object and array
keyword payloads are copied when a schema is constructed and when typed views
are returned. Empty required-property lists, false flags and explicit null data
remain distinct from absent keywords. No defaults are inserted.

```mbt check
///|
test {
  let raw = @json.parse(
      "{\"properties\":{\"$id\":false},\"default\":{\"type\":17},\"custom\":{\"$ref\":\"literal data\"},\"x-vendor\":false}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let schema = @schema.Schema::from_json(raw).unwrap()
  guard schema.kind() is @schema.ObjectSchema(object) else { fail("object") }
  assert_eq(object.additional_fields().length(), 1)
  assert_eq(object.extensions().entries().length(), 1)
  guard object.keyword("properties").unwrap() is @schema.Properties(entries) else {
    fail("properties")
  }
  assert_eq(entries[0].0, "$id")
  assert_true(entries[0].1.kind() is @schema.BooleanSchema(false))
  assert_true(schema.to_json().equals(raw).unwrap())
}
```

Only schema-bearing positions are traversed. Dictionary keys are data names.
Defaults, examples, enum values, constants, arbitrary extensions and unknown
keyword values remain exact instance values. Unknown keywords are retained in
`additional_fields`; `x-*` fields use the same checked `Extensions` type as
OpenRPC document objects.

Draft-07 `$ref` siblings are retained raw and ignored for schema assertion
semantics. A declared unsupported dialect has an explicit alternative and is
not decoded as draft-07. No reference triggers filesystem or network access.

```mbt check
///|
test {
  let raw = @json.parse("{\"type\":17}").unwrap().lower().unwrap()
  assert_true(@schema.Schema::from_json(raw) is Err(_))
  let report = @schema.validate_json(raw, root=raw)
  assert_true(report.diagnostics().any(d => d.code() == @json.InvalidSchema))
}
```

`validate_json` reports malformed untyped documents without requiring an invalid
typed Schema. `validate` accepts a typed Schema. Both check every draft-07
keyword form and the frozen metaschema's local constraints. Enum values must be
nonempty and mathematically unique, including nested arrays and unordered
objects. Unknown keywords are legal and opaque. Contradictory instance bounds
can describe an unsatisfiable schema; they do not make the schema malformed.

```mbt check
///|
test {
  let raw = @json.parse("{\"enum\":[1,1.00]}").unwrap().lower().unwrap()
  let report = @schema.validate_json(raw, root=raw)
  assert_true(report.is_complete())
  assert_eq(report.diagnostics()[0].path(), ["enum", "1"])
  let distinct = @json.parse(
      "{\"enum\":[9007199254740992,9007199254740993],\"minimum\":10,\"maximum\":1}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let report = @schema.validate_json(distinct, root=distinct)
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
}
```

An absent dialect means draft-07. The recognized aliases are
`http://json-schema.org/draft-07/schema` and its HTTPS spelling, with or without
an empty `#` fragment. Other dialects are retained and report
`UnsupportedDialect` with incomplete coverage. `is_complete()` means the
requested checks ran; a complete report can contain validation failures.

`check_pattern` checks ECMA-262 ninth edition, 2018, without flags, including
Annex B. Its Unicode identifier data is fixed at Unicode 10.0.0. This includes
lookahead, lookbehind, named groups, numeric and named backreferences, and
legacy escape/range syntax outside the installed matcher's subset. Pattern
strings have no `/.../flags` wrapper: those characters are ordinary pattern
data. Unicode-mode property escapes and later-edition modifiers are not enabled.
For example, `\\p{L}` has its legacy no-flags meaning, not a Unicode property
meaning. No pattern is matched or executed.

```mbt check
///|
test {
  assert_true(@schema.check_pattern("(?<word>x)\\k<word>") is Ok(_))
  assert_true(@schema.check_pattern("(?<=x)y") is Ok(_))
  guard @schema.check_pattern("[z-a]") is Err(error) else {
    fail("invalid character range")
  }
  assert_eq(error.code(), @json.InvalidSchema)
  assert_true(error.offset() >= 0)
}
```

`PatternError.offset()` counts UTF-16 units in the decoded pattern. Schema
diagnostics retain the keyword pointer and include that offset in the message.
It is not a JSON source span. `patternProperties` checks its dictionary keys
as patterns; ordinary `properties` keys remain literal names. A schema's
`format`, `contentEncoding` and `contentMediaType` are typed annotations. The
library does not apply them, or the schema itself, to instance values.

An adapter can explicitly submit a schema inside an extension with its original
document root, pointer and retrieval base. The library never searches arbitrary
payloads for a property called `schema`.

```mbt check
///|
test {
  let root = @json.parse(
      "{\"x-vendor\":{\"schema\":{\"$ref\":\"https://schemas.example/document#/definitions/S\"}},\"definitions\":{\"S\":false}}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let embedded = root.get("x-vendor").unwrap().get("schema").unwrap()
  let report = @schema.validate_json(
    embedded,
    root~,
    path=["x-vendor", "schema"],
    base=Some(
      @reference.UriReference::parse("https://schemas.example/document").unwrap(),
    ),
  )
  assert_true(report.is_complete())
  assert_eq(report.diagnostics().length(), 0)
}
```

References resolve through draft-07 `$id` scopes and an explicit
`@reference.ResourceSet`. Each `$ref` uses the nearest enclosing `$id` as its
base. A `$id` next to `$ref` is ignored, as draft-07 requires. Values under
literal or unknown keywords never establish scopes. When `base` names a
registered resource, that resource is the physical document. Otherwise `root`
is an unnamed input document, named by `base` when one is given. The submitted
schema keeps the physical identity at `path` only when it equals the value
there exactly. Otherwise it is checked as a separate input and `path` is
advisory. Each location is checked once, even when several access paths reach
it.

```mbt check
///|
test {
  let raw = @json.parse(
      "{\"$id\":\"http://x.test/root.json\",\"definitions\":{\"B\":{\"$id\":\"b.json\",\"definitions\":{\"X\":{\"type\":\"string\"}},\"properties\":{\"p\":{\"$ref\":\"#/definitions/X\"},\"e\":{\"$ref\":\"https://ext.test/e.json\"}}}}}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let open = @schema.validate_json(raw, root=raw)
  assert_false(open.references_complete())
  assert_eq(open.diagnostics()[0].code(), @json.UnavailableResource)
  let external = @reference.Resource::new(
    @reference.UriReference::parse("https://ext.test/e.json").unwrap(),
    @json.Value::boolean(true),
    schema_roots=[@reference.JsonPointer::parse("").unwrap()],
  ).unwrap()
  let closed = @schema.validate_json(
    raw,
    root=raw,
    resources=@reference.ResourceSet::new([external]).unwrap(),
  )
  assert_true(closed.is_complete())
  assert_eq(closed.diagnostics().length(), 0)
  assert_eq(closed.resolutions().length(), 2)
}
```

`is_complete` covers every check. `references_complete` covers reference and
identifier resolution alone. An unsupplied resource (`UnavailableResource`) or a
relative reference with no base (`MissingBaseUri`) leaves both incomplete. A
broken pointer, an unknown identifier fragment or a duplicate identifier is a
complete failure. No resource is fetched. This development module is not a
qualified release candidate.

Validation defaults are 10,000 schema nodes, 4,096 reference edges, 256 findings
and 1,000,000 enum comparison work units. A comparison charges the sum of both
values' canonical UTF-16 lengths before exact equality. Shared `Limits` also
bound JSON depth, source/output units, value nodes and number tokens. The
stricter explicit/shared finding bound applies. Exhaustion reports
`LimitExceeded` and incomplete coverage. Regex checks use the shared source,
group/reference node, nesting and quantifier-digit limits. Limits can be
increased explicitly; unlimited limits do not promise available host memory.

The four-target source consumer compares an 81-case syntax corpus with pinned
`@eslint-community/regexpp@4.12.2` in ECMAScript2018 mode. Additional exact
quantifier tests use decimal comparisons beyond host floating-point precision.
The independent parser is an unpublished qualification dependency. Generated
identifier data is covered by [the Unicode license](../UNICODE-LICENSE.txt);
the published library imports only MoonBit core and its own packages.

A second corpus compares keyword shapes with pinned `ajv@8.17.1` using the
unchanged frozen draft-07 metaschema. Formats are disabled in this shape check;
the separate portable syntax corpus checks regexes. Two explicit difference
cases record ignored draft-07 reference siblings and adjacent large enum
integers that the host JSON parser rounds together. The MoonBit consumer
receives the original numeric text and checks its own expected result. This
does not replace later full OpenRPC artifact/profile qualification.
