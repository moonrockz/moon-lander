# URI references and JSON Pointers

`UriReference` checks the generic ASCII URI grammar in RFC 3986. It retains
scheme, authority, user information, host alternative, exact port token, path,
query and fragment spelling. Empty queries and fragments remain distinct from
absent ones. Generic URI ports have no assumed transport range. IPv6 and
IPvFuture literals are checked; zone identifiers from later URI extensions are
outside this grammar.

```mbt check
///|
test {
  let base = @reference.UriReference::parse("HTTPS://Example.test/a/b").unwrap()
  let relative = @reference.UriReference::parse("../c%2fd?#fragment").unwrap()
  let resolved = relative.resolve(base).unwrap()
  assert_eq(resolved.text(), "HTTPS://Example.test/c%2fd?#fragment")
  assert_eq(resolved.identity(), "https://example.test/c%2Fd?#fragment")
  assert_eq(relative.text(), "../c%2fd?#fragment")
  assert_eq(resolved.query(), Some(""))
}
```

URI resolution follows RFC 3986 section 5.2 and computes an absolute URI; it
does not retrieve or inspect a resource. `identity()` is separate from retained
text. It folds scheme and host case, normalizes percent hex and unreserved
characters, and removes dot segments from absolute or rooted paths. Relative
rootless paths need a base before removing dots. It does not guess default
ports, equate HTTP and HTTPS, follow redirects or perform DNS lookup.

`Reference` adds JSON-target fragment meaning to a URI. Its alternatives are
the whole resource, a checked JSON Pointer, or a decoded named identifier.
`JsonPointer` uses plain RFC 6901 escaping; URI percent decoding belongs to the
Reference layer. A named identifier remains unresolved until a resource/scope
index supplies its target.

```mbt check
///|
test {
  let parts = ["a/b", "~key", "🛰"]
  let pointer = @reference.JsonPointer::from_tokens(parts).unwrap()
  parts.clear()
  assert_eq(pointer.to_string(), "/a~1b/~0key/🛰")
  let reference = @reference.Reference::parse("#/%7E01").unwrap()
  assert_eq(reference.local_pointer().unwrap().tokens(), ["~1"])
  let url = @reference.UriReference::parse("https://example.test/page#/raw~2").unwrap()
  assert_eq(url.fragment(), Some("/raw~2"))
  assert_true(@reference.Reference::from_uri(url) is Err(_))
}
```

Metadata URLs, editor/dialect identifiers and example `externalValue` use the
general URI type because their fragments need not identify JSON values.
OpenRPC and schema `$ref` values use `Reference`. Both retain original text for
writing. Server URL templates remain uninterpreted strings.

Checked URI/pointer operations accept shared `Limits`. Defaults allow 8,388,608
UTF-16 source/output units and 100,000 value/token nodes; pointer depth is at
most 256 tokens. Resolution bounds both input URIs, merged paths and output
before growing their buffers. Pointer lookup inspects immutable children without
copying whole array/object views and constructs a diagnostic path only on
failure. Raising bounds on a containing document/schema is inherited by its
decoders, and typed getters retain values accepted under those chosen bounds.

## Explicit resources

A `Resource` is an immutable JSON value registered under an absolute,
fragment-free retrieval URI and optional aliases. The value can be a whole
document or an extracted fragment. Aliases name the same resource; they do not
add a second retrieval base. `schema_roots` declares which locations hold
draft-07 schemas; nothing else in a generic resource is treated as a schema.

A `ResourceSet` indexes resources by `identity()` and has an optional root base
URI. Two registrations with the same normalized identity are a
`ConflictingIdentifier` error. Constructors copy their input arrays and getters
return copies. Registration counts and the total node count of all values are
checked against `Limits` before the index is built.

```mbt check
///|
test {
  let doc = @json.parse("{\"defs\":{\"a/b\":[1,{\"ok\":true}]}}")
    .unwrap()
    .lower()
    .unwrap()
  let resource = @reference.Resource::new(
    @reference.UriReference::parse("https://example.test/api/doc.json").unwrap(),
    doc,
    aliases=[
      @reference.UriReference::parse("HTTPS://Example.test/api/./doc.json").unwrap(),
    ],
  ).unwrap()
  let set = @reference.ResourceSet::new(
    [resource],
    root_base=Some(
      @reference.UriReference::parse("https://example.test/api/").unwrap(),
    ),
  ).unwrap()
  let found = set.resolve(
    @reference.Reference::parse("doc.json#/defs/a~1b/1").unwrap(),
  )
  assert_true(found.complete())
  let target = found.target().unwrap()
  assert_eq(
    target.resource().unwrap().text(),
    "https://example.test/api/doc.json",
  )
  assert_eq(@json.write(target.target()).unwrap(), "{\"ok\":true}")
  let absent = set.resolve(
    @reference.Reference::parse("file:///etc/passwd").unwrap(),
  )
  assert_false(absent.complete())
  assert_eq(absent.diagnostics()[0].code(), @json.UnavailableResource)
}
```

`ResourceSet::resolve` resolves one reference. A relative reference uses the
given `base`, otherwise the root base. Results are a `Resolution`: the owned
target `Location` (resource URI, pointer and immutable value), the chain of
`ReferenceStep` sites with their absolute URIs, diagnostics, and a `complete`
flag. Missing input gives an incomplete result: `MissingBaseUri` when there is
no absolute base, and `UnavailableResource` when a resource was not supplied.
Broken pointers (`UnresolvedReference`) and malformed syntax
(`InvalidReference`) are complete failures. A URI scheme never causes an action;
`file:`, `javascript:` and unknown schemes are only lookup keys.

`ResourceSet::follow` follows a chain while a caller-supplied function reports
that a target is itself a reference. Each later reference resolves against the
URI of the resource that holds it. Revisiting a location is a `ReferenceCycle`.
A chain longer than `max_depth` is incomplete with `LimitExceeded`. The generic
layer never decides by itself that a `$ref` member is a reference, so `$ref`
inside literal data is not followed. Typed schema and OpenRPC resolution supply
that decision.

## Draft-07 identifier scopes

The generic resolver reports identifier fragments such as `#node` as incomplete
`UnsupportedCheck`. `SchemaIndex` resolves them. It walks the declared schema
roots of each resource, plus an optional unnamed input document, through
draft-07 subschema positions only. A `$id` with a URI part names a schema
resource at that location and becomes the scope for its subschemas. A `$id`
plain-name fragment names a location within the current scope. Literal and
unknown keywords, `$ref` siblings and declared foreign dialects are not indexed.

```mbt check
///|
test {
  let doc = @json.parse(
      "{\"$id\":\"http://x.test/root.json\",\"definitions\":{\"B\":{\"$id\":\"b.json\",\"definitions\":{\"X\":{\"$id\":\"#x\"}}}}}",
    )
    .unwrap()
    .lower()
    .unwrap()
  let index = @reference.SchemaIndex::new(
    @reference.ResourceSet::empty(),
    input=Some(doc),
    input_roots=[@reference.JsonPointer::parse("").unwrap()],
  )
  let b = index.resolve(
    @reference.Reference::parse("http://x.test/b.json").unwrap(),
  )
  let scope = index.scope(b.target().unwrap())
  assert_eq(scope.unwrap().text(), "http://x.test/b.json")
  for
    text in ["#x", "#/definitions/X", "root.json#/definitions/B/definitions/X"] {
    let found = index.resolve(
      @reference.Reference::parse(text).unwrap(),
      base=scope,
    )
    assert_eq(
      found.target().unwrap().identity(),
      "#/definitions/B/definitions/X",
    )
  }
}
```

Every access path resolves to the same owned `Location`: the physical resource
(None for the unnamed input) and the pointer within it. Resolving never copies
or expands a schema. An identifier that claims a location already named by
another identifier or registered resource is a `ConflictingIdentifier`; the
first binding is kept. A relative `$id` without a base is `MissingBaseUri`. A
non-plain-name fragment such as `#/a`, which draft-07 leaves undefined, is kept
and reported as incomplete `UnsupportedCheck`. In an unnamed input with no
base, a relative `$id` names its own location: fragment-only references inside
it resolve there, and references that change the path report `MissingBaseUri`.
Schemas reached by `$ref` are indexed too, even outside the declared roots, and
nested roots are walked after their ancestors. Plain names are keyed by the
location that sets their scope, so retrieval URIs, aliases and `$id` spellings
of a document all reach them. Typed OpenRPC
targets are resolved by the root package's document validation. This
development module is not a qualified release candidate.
