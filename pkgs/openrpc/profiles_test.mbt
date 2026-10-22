///|
fn closed(
  document : @openrpc.Document,
  profile : @openrpc.ValidationProfile,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
) -> @openrpc.ClosedValidation {
  @openrpc.validate_closed(document, profile~, resources~)
}

///|
test "profile success does not hide artifact disagreement" {
  let document = versioned("1.3.2", external_example)
  let specification = closed(document, @openrpc.Specification)
  let wrapper = specification.document().unwrap()
  assert_eq(wrapper.report().artifact(), @openrpc.Failed)
  assert_eq(wrapper.profile(), @openrpc.Specification)
  assert_eq(wrapper.version().to_string(), "1.3.2")
  assert_eq(wrapper.resources().length(), 0)
  let compatibility = closed(document, @openrpc.MetaschemaCompatibility)
  assert_true(compatibility.document() is None)
  assert_eq(compatibility.report().artifact(), @openrpc.Failed)
}

///|
test "compatibility cannot excuse unrelated semantic errors" {
  for
    body in [
      "\"methods\":[{\"name\":\"a\",\"params\":[]},{\"name\":\"a\",\"params\":[]}]",
      "\"methods\":[{\"name\":\"a\",\"params\":[],\"errors\":[{\"code\":1,\"message\":\"x\"},{\"code\":1,\"message\":\"y\"}]}]",
    ] {
    for
      profile in [@openrpc.Specification, @openrpc.MetaschemaCompatibility] {
      let result = closed(versioned("1.4.0", body), profile)
      assert_eq(result.report().normative(), @openrpc.Failed, msg=body)
      assert_true(result.document() is None, msg=body)
    }
  }
}

///|
test "open resource coverage is not a closed validation proof" {
  let document = versioned(
    "1.4.0",
    "\"methods\":[{\"$ref\":\"https://ext.test/m.json#/m\"}]",
  )
  for profile in [@openrpc.Specification, @openrpc.MetaschemaCompatibility] {
    let result = closed(document, profile)
    assert_eq(result.report().references(), @openrpc.Incomplete)
    assert_true(result.document() is None)
  }
  let resource = @reference.Resource::new(
    uri("https://ext.test/m.json"),
    exact("{\"m\":{\"name\":\"ext\",\"params\":[]}}"),
  ).unwrap()
  let resources = @reference.ResourceSet::new([resource]).unwrap()
  let result = closed(document, @openrpc.Specification, resources~)
  assert_eq(
    result.document().unwrap().resources().map(u => u.text()),
    ["https://ext.test/m.json"],
  )
}

///|
test "interior optional parameters have explicit profile results" {
  let document = versioned(
    "1.3.2",
    "\"methods\":[{\"name\":\"a\",\"params\":[{\"name\":\"o\",\"required\":false,\"schema\":true},{\"name\":\"r\",\"required\":true,\"schema\":true}]}]",
  )
  let strict = closed(document, @openrpc.Specification)
  assert_eq(strict.report().normative(), @openrpc.Failed)
  assert_true(strict.document() is None)
  let compatible = closed(document, @openrpc.MetaschemaCompatibility)
  let order = compatible
    .report()
    .findings()
    .filter(f => f.diagnostic().code() == @exact.ParameterOrder)
  assert_eq(order.map(f => f.severity()), [@openrpc.Warning])
  let wrapper = compatible.document().unwrap()
  assert_eq(wrapper.profile(), @openrpc.MetaschemaCompatibility)
  guard wrapper.document().methods()[0] is @openrpc.Inline(method_) else {
    fail("expected an inline method")
  }
  assert_eq(
    method_
    .params()
    .map(p => {
      guard p is @openrpc.Inline(d) else { abort("inline") }
      (d.name(), d.required())
    }),
    [("o", Some(false)), ("r", Some(true))],
  )
}

///|
test "truncated findings never produce a wrapper" {
  let document = versioned(
    "1.4.0",
    "\"methods\":[{\"name\":\"a\",\"params\":[],\"foo\":1,\"bar\":2}]",
  )
  let limits = @exact.Limits::new(max_findings=1)
  for profile in [@openrpc.Specification, @openrpc.MetaschemaCompatibility] {
    let result = @openrpc.validate_closed(document, profile~, limits~)
    assert_true(result.document() is None)
  }
}
