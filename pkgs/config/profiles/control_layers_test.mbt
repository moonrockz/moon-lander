///|
test "control layers accept object roots and report the input origin for invalid roots" {
  ignore(@profiles.ControlLayer::new(@config.fields([]), origin()))
  for value in [@config.list([]), @config.int(1)] {
    try {
      ignore(@profiles.ControlLayer::new(value, origin()))
      fail("non-object control layer accepted")
    } catch {
      @config.InvalidRoot(origin=path, ..) => assert_eq(path, "/work/acme.toml")
      error => raise error
    }
  }
}

///|
test "layered control resolution keeps winning origins and exact source authorities" {
  let first = { ..origin(), location: Some("/work/acme.json") }
  let second = origin()
  let inputs = [
    @profiles.ControlLayer::new(@config.ConfigValue::from_json({ "profiles": { "active": ["earlier"] } }), first),
    @profiles.ControlLayer::new(@config.ConfigValue::from_json({ "profiles": { "active": ["later"] } }), second),
  ]
  let layers = @profiles.ControlLayers::new(inputs)
  inputs.clear()
  let resolution = @profiles.resolve_layers(@profiles.Policy::new(), @profiles.SelectionInput::new(Unspecified), layers)
  assert_eq(active(resolution), ["later"])
  assert_eq(resolution.selector(), BaseActive(second))
  assert_true(resolution.permits_controls(first))
  assert_true(resolution.permits_controls(second))
  assert_false(resolution.permits_controls({ ..first, kind: File(Member), priority: 350 }))
  let legacy = @profiles.resolve(@profiles.Policy::new(), Unspecified, controls=controls({ "profiles": { "active": ["legacy"] } }))
  assert_true(legacy.permits_controls(origin()))
  let disabled = @profiles.resolve_layers(@profiles.Policy::new(), @profiles.SelectionInput::new(Disabled), layers)
  assert_true(disabled.disabled())
  assert_false(disabled.permits_controls(first))
}

///|
test "empty layered bases and empty profile tables need no synthetic control origin" {
  let policy = @profiles.Policy::new()
  let input = @profiles.SelectionInput::new(Unspecified)
  assert_eq(active(@profiles.resolve_layers(policy, input, @profiles.ControlLayers::new([]))), [])
  let layers = @profiles.ControlLayers::new([@profiles.ControlLayer::new(@config.ConfigValue::from_json({ "profiles": {} }), origin())])
  let result = @profiles.resolve_layers(policy, input, layers)
  assert_eq(active(result), [])
  assert_eq(result.controls(), [Control(origin(), @config.KeyPath::parse("profiles"))])
}

///|
test "raw layered null controls retain the existing typed shape failures" {
  let cases : Array[(Json, @config.ProfileRule)] = [
    ({ "profiles": Json::null() }, @config.ProfileRule::ExpectedTable),
    ({ "profiles": { "active": Json::null() } }, ExpectedList),
    ({ "profiles": { "groups": { "alpha": Json::null() } } }, ExpectedList),
    ({ "profiles": { "default": ["${SECRET}"] } }, NonLiteral),
  ]
  for (value, rule) in cases {
    let layers = @profiles.ControlLayers::new([@profiles.ControlLayer::new(@config.ConfigValue::from_json(value), origin())])
    expect_rule(() => ignore(@profiles.resolve_layers(@profiles.Policy::new(), @profiles.SelectionInput::new(Unspecified), layers)), rule)
  }
}

///|
test "winning literal null controls fail and an earlier invalid control may be replaced" {
  let first = { ..origin(), location: Some("/work/acme.json") }
  let last = origin()
  let invalid = @config.ConfigValue::from_json({ "profiles": { "active": Json::null() } })
  let valid = @config.ConfigValue::from_json({ "profiles": { "active": ["metrics"] } })
  let policy = @profiles.Policy::new()
  let input = @profiles.SelectionInput::new(Unspecified)
  let replaced = @profiles.ControlLayers::new([@profiles.ControlLayer::new(invalid, first), @profiles.ControlLayer::new(valid, last)])
  assert_eq(active(@profiles.resolve_layers(policy, input, replaced)), ["metrics"])
  let bad_winner = @profiles.ControlLayers::new([@profiles.ControlLayer::new(valid, first), @profiles.ControlLayer::new(invalid, last)])
  try {
    ignore(@profiles.resolve_layers(policy, input, bad_winner))
    fail("null winning control accepted")
  } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), ExpectedList)
      assert_eq(failure.origin(), Control(last, @config.KeyPath::parse("profiles.active")))
    }
    error => raise error
  }
}
