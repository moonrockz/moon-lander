///|
fn json_value(text : String) -> @json.Value {
  @json.parse(text).unwrap().lower().unwrap()
}

///|
fn uri(text : String) -> @reference.UriReference {
  @reference.UriReference::parse(text).unwrap()
}

///|
fn ref_(text : String) -> @reference.Reference {
  @reference.Reference::parse(text).unwrap()
}

///|
fn sample_set() -> @reference.ResourceSet {
  let document = @reference.Resource::new(
    uri("https://example.test/api/doc.json"),
    json_value(
      "{\"a/b\":{\"m~n\":[10,{\"x\":true}]},\"%\":1,\"\\uD83D\\uDE00\":2}",
    ),
  ).unwrap()
  let schema = @reference.Resource::new(
    uri("https://example.test/schemas/pet.json"),
    json_value("{\"type\":\"object\"}"),
    aliases=[uri("HTTPS://Example.TEST/schemas/./%70et.json")],
  ).unwrap()
  @reference.ResourceSet::new(
    [document, schema],
    root_base=Some(uri("https://example.test/api/doc.json")),
  ).unwrap()
}

///|
test "explicit resources resolve escaped pointers, arrays and whole targets" {
  let set = sample_set()
  let found = set.resolve(ref_("#/a~1b/m~0n/1/x"))
  assert_true(found.complete())
  assert_eq(found.diagnostics().length(), 0)
  let target = found.target().unwrap()
  assert_eq(
    target.resource().unwrap().text(),
    "https://example.test/api/doc.json",
  )
  assert_eq(target.pointer().tokens(), ["a/b", "m~n", "1", "x"])
  assert_eq(@json.write(target.target()).unwrap(), "true")
  let percent = set.resolve(ref_("#/%25")).target().unwrap()
  assert_eq(@json.write(percent.target()).unwrap(), "1")
  let astral = set.resolve(ref_("#/%F0%9F%98%80")).target().unwrap()
  assert_eq(@json.write(astral.target()).unwrap(), "2")
  for text in ["#", "", "doc.json", "doc.json#"] {
    let whole = set.resolve(ref_(text))
    assert_eq(whole.target().unwrap().pointer().tokens(), [], msg=text)
  }
  let item = set.resolve(ref_("#/a~1b/m~0n/0")).target().unwrap()
  assert_eq(@json.write(item.target()).unwrap(), "10")
}

///|
test "aliases and relative references share one normalized resource identity" {
  let set = sample_set()
  for
    text in [
      "../schemas/pet.json#/type", "https://EXAMPLE.test/schemas/pet.json#/type",
    ] {
    let found = set.resolve(ref_(text))
    let target = found.target().unwrap()
    assert_eq(
      target.resource().unwrap().text(),
      "https://example.test/schemas/pet.json",
    )
    assert_eq(@json.write(target.target()).unwrap(), "\"object\"", msg=text)
  }
  let explicit = set.resolve(
    ref_("pet.json"),
    base=Some(uri("https://example.test/schemas/other.json")),
  )
  assert_true(explicit.target() is Some(_))
  assert_eq(explicit.chain().length(), 1)
  assert_eq(
    explicit.chain()[0].resolved().unwrap().text(),
    "https://example.test/schemas/pet.json",
  )
  assert_true(
    set.get(uri("https://example.test/schemas/%2E/pet.json#ignored")) is Some(_),
  )
}

///|
test "missing bases and unavailable resources are incomplete, never fetched" {
  let empty = @reference.ResourceSet::empty()
  let missing = empty.resolve(ref_("other.json#/a"))
  assert_false(missing.complete())
  assert_true(missing.target() is None)
  assert_eq(missing.diagnostics()[0].code(), @json.MissingBaseUri)
  assert_eq(
    empty.resolve(ref_("#/a")).diagnostics()[0].code(),
    @json.MissingBaseUri,
  )
  let set = sample_set()
  for
    text in [
      "https://example.test/absent.json", "file:///etc/passwd#/root", "javascript:alert(1)",
      "http://example.test/api/doc.json", "https://example.test:443/api/doc.json",
    ] {
    let found = set.resolve(ref_(text))
    assert_false(found.complete(), msg=text)
    assert_true(found.target() is None, msg=text)
    assert_eq(
      found.diagnostics()[0].code(),
      @json.UnavailableResource,
      msg=text,
    )
  }
}

///|
test "broken pointers fail completely with their own code" {
  let set = sample_set()
  for
    text in [
      "#/missing", "#/a~1b/m~0n/-", "#/a~1b/m~0n/01", "#/a~1b/m~0n/2", "#/%25/x",
    ] {
    let found = set.resolve(ref_(text))
    assert_true(found.complete(), msg=text)
    assert_true(found.target() is None, msg=text)
    assert_eq(
      found.diagnostics()[0].code(),
      @json.UnresolvedReference,
      msg=text,
    )
  }
}

///|
test "identifier fragments need a schema scope and stay incomplete here" {
  let found = sample_set().resolve(ref_("#node"))
  assert_false(found.complete())
  assert_eq(found.diagnostics()[0].code(), @json.UnsupportedCheck)
}

///|
test "resource construction requires absolute fragment-free names and real roots" {
  let value = json_value("{\"definitions\":{\"a\":{}}}")
  for
    text in [
      "relative.json", "https://example.test/a#", "https://example.test/a#/x",
    ] {
    let made = @reference.Resource::new(uri(text), value)
    assert_eq(made.unwrap_err().code(), @json.InvalidReference, msg=text)
    let aliased = @reference.Resource::new(
      uri("https://example.test/a"),
      value,
      aliases=[uri(text)],
    )
    assert_eq(aliased.unwrap_err().code(), @json.InvalidReference, msg=text)
  }
  let root = @reference.JsonPointer::parse("/definitions/a").unwrap()
  let made = @reference.Resource::new(uri("https://example.test/a"), value, schema_roots=[
    root,
  ]).unwrap()
  assert_eq(made.schema_roots()[0].tokens(), ["definitions", "a"])
  let absent = @reference.Resource::new(uri("https://example.test/a"), value, schema_roots=[
    @reference.JsonPointer::parse("/definitions/b").unwrap(),
  ])
  assert_eq(absent.unwrap_err().code(), @json.UnresolvedReference)
}

///|
test "conflicting normalized registrations are rejected" {
  let value = json_value("{}")
  let first = @reference.Resource::new(uri("https://example.test/a"), value).unwrap()
  let second = @reference.Resource::new(uri("https://example.test/b"), value, aliases=[
    uri("HTTPS://example.test/./a"),
  ]).unwrap()
  let conflict = @reference.ResourceSet::new([first, second])
  assert_eq(conflict.unwrap_err().code(), @json.ConflictingIdentifier)
  let same = @reference.ResourceSet::new([first, first])
  assert_eq(same.unwrap_err().code(), @json.ConflictingIdentifier)
  let self_alias = @reference.Resource::new(
    uri("https://example.test/c"),
    value,
    aliases=[uri("https://example.test/c"), uri("https://example.test/./c")],
  ).unwrap()
  assert_true(@reference.ResourceSet::new([first, self_alias]) is Ok(_))
}

///|
test "inputs and getters are defensive copies" {
  let aliases = [uri("https://example.test/alias")]
  let roots = [@reference.JsonPointer::parse("").unwrap()]
  let resource = @reference.Resource::new(
    uri("https://example.test/a"),
    json_value("{}"),
    aliases~,
    schema_roots=roots,
  ).unwrap()
  aliases.push(uri("https://example.test/later"))
  roots.clear()
  assert_eq(resource.aliases().length(), 1)
  assert_eq(resource.schema_roots().length(), 1)
  resource.aliases().clear()
  assert_eq(resource.aliases().length(), 1)
  let resources = [resource]
  let set = @reference.ResourceSet::new(resources).unwrap()
  resources.clear()
  assert_eq(set.resources().length(), 1)
  set.resources().clear()
  assert_eq(set.resources().length(), 1)
  assert_true(set.get(uri("https://example.test/alias")) is Some(_))
}

///|
fn ref_member(location : @reference.Location) -> @reference.Reference? {
  match location.target().get("$ref") {
    Some(value) =>
      match value.text() {
        Some(text) => @reference.Reference::parse(text).to_option()
        None => None
      }
    None => None
  }
}

///|
test "followed chains record each site and stop at cycles" {
  let chain = @reference.Resource::new(
    uri("https://example.test/chain.json"),
    json_value(
      "{\"a\":{\"$ref\":\"#/b\"},\"b\":{\"$ref\":\"other.json#/c\"},\"x\":{\"$ref\":\"#/y\"},\"y\":{\"$ref\":\"#/x\"},\"s\":{\"$ref\":\"#/s\"}}",
    ),
  ).unwrap()
  let other = @reference.Resource::new(
    uri("https://example.test/other.json"),
    json_value("{\"c\":{\"type\":\"string\"}}"),
  ).unwrap()
  let set = @reference.ResourceSet::new(
    [chain, other],
    root_base=Some(uri("https://example.test/chain.json")),
  ).unwrap()
  let found = set.follow(ref_("#/a"), ref_member)
  assert_true(found.complete())
  let target = found.target().unwrap()
  assert_eq(
    target.resource().unwrap().text(),
    "https://example.test/other.json",
  )
  assert_eq(target.pointer().tokens(), ["c"])
  let steps = found.chain()
  assert_eq(steps.length(), 3)
  assert_true(steps[0].site() is None)
  assert_eq(steps[1].site().unwrap().pointer().tokens(), ["a"])
  assert_eq(steps[2].site().unwrap().pointer().tokens(), ["b"])
  assert_eq(steps[2].reference().text(), "other.json#/c")
  let cycle = set.follow(ref_("#/x"), ref_member)
  assert_true(cycle.complete())
  assert_true(cycle.target() is None)
  assert_eq(cycle.diagnostics()[0].code(), @json.ReferenceCycle)
  let self_cycle = set.follow(ref_("#/s"), ref_member)
  assert_true(self_cycle.target() is None)
  assert_eq(self_cycle.diagnostics()[0].code(), @json.ReferenceCycle)
}

///|
test "long chains and large registrations exhaust explicit bounds" {
  let members = []
  for i in 0..<20 {
    members.push("\"n\{i}\":{\"$ref\":\"#/n\{i + 1}\"}")
  }
  members.push("\"n20\":{}")
  let resource = @reference.Resource::new(
    uri("https://example.test/long.json"),
    json_value("{" + members.join(",") + "}"),
  ).unwrap()
  let set = @reference.ResourceSet::new(
    [resource],
    root_base=Some(uri("https://example.test/long.json")),
  ).unwrap()
  assert_true(set.follow(ref_("#/n0"), ref_member).target() is Some(_))
  let bounded = set.follow(
    ref_("#/n0"),
    ref_member,
    limits=@json.Limits::new(max_depth=5),
  )
  assert_false(bounded.complete())
  assert_true(bounded.target() is None)
  assert_eq(bounded.diagnostics()[0].code(), @json.LimitExceeded)
  assert_eq(
    @reference.Resource::new(
      uri("https://example.test/big.json"),
      json_value("[1,2,3,4,5]"),
      limits=@json.Limits::new(max_nodes=3),
    )
    .unwrap_err()
    .code(),
    @json.LimitExceeded,
  )
  let small = []
  for i in 0..<4 {
    small.push(
      @reference.Resource::new(
        uri("https://example.test/r\{i}"),
        json_value("[1,2]"),
      ).unwrap(),
    )
  }
  assert_eq(
    @reference.ResourceSet::new(small, limits=@json.Limits::new(max_nodes=10))
    .unwrap_err()
    .code(),
    @json.LimitExceeded,
  )
  assert_true(
    @reference.ResourceSet::new(small, limits=@json.Limits::new(max_nodes=12))
    is Ok(_),
  )
}
