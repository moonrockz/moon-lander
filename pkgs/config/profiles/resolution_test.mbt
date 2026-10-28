///|
fn names(texts : Array[String]) -> @config.ProfileNames raise @config.ConfigError {
  @config.ProfileNames::new(texts.map(text => @config.ProfileName::parse(text)))
}

///|
fn selected(texts : Array[String]) -> @config.ProfileSelection raise @config.ConfigError {
  Selected(names(texts))
}

///|
fn active(result : @config.ProfileResolution) -> Array[String] {
  result.active().names().map(name => name.to_string())
}

///|
fn origin() -> @config.Origin {
  { kind: File(Workspace), source: "acme", priority: 300, location: Some("/work/acme.toml") }
}

///|
fn controls(json : Json) -> (@config.ConfigValue, @config.Origin) raise @config.ConfigError {
  (@config.ConfigValue::from_json(json), origin())
}

///|
fn expect_rule(run : () -> Unit raise @config.ConfigError, rule : @config.ProfileRule) -> Unit raise {
  try { run() } catch {
    @config.Profile(failure~) => assert_eq(failure.rule(), rule)
    error => raise error
  } noraise { _ => fail("expected a typed profile failure") }
}

///|
test "selection precedence keeps includes and distinguishes empty and disabled" {
  let policy = @profiles.Policy::new() |> @profiles.fallback(names(["fallback"])) |> @profiles.includes(names(["policy"]))
  let file = controls({ "profiles": { "active": ["active"], "default": ["default"], "include": ["file"] } })
  assert_eq(active(@profiles.resolve(policy, selected(["cli"]), variable=("ACME_PROFILES", "variable"), controls=file)), ["policy", "file", "cli"])
  assert_eq(active(@profiles.resolve(policy, Unspecified, variable=("ACME_PROFILES", "variable"), controls=file)), ["policy", "file", "variable"])
  let from_base = @profiles.resolve(policy, Unspecified, controls=file)
  assert_eq(active(from_base), ["policy", "file", "active"])
  assert_eq(from_base.selector(), BaseActive(origin()))
  let defaults = controls({ "profiles": { "default": ["default"], "include": ["file"] } })
  assert_eq(active(@profiles.resolve(policy, Unspecified, controls=defaults)), ["policy", "file", "default"])
  assert_eq(active(@profiles.resolve(policy, selected([]), controls=defaults)), ["policy", "file"])
  let empty_base = controls({ "profiles": { "active": [], "default": ["default"], "include": ["file"] } })
  assert_eq(active(@profiles.resolve(policy, Unspecified, controls=empty_base)), ["policy", "file"])
  assert_eq(active(@profiles.resolve(policy, Unspecified)), ["policy", "fallback"])
  let disabled = @profiles.resolve(policy, Disabled, controls=controls({ "profiles": { "active": 42 } }))
  assert_eq(active(disabled), [])
  assert_true(disabled.disabled())
  let blank = @profiles.resolve(policy, Unspecified, variable=("ACME_PROFILES", " \t\r\n"), controls=controls({ "profiles": false }))
  assert_true(blank.disabled())
  assert_eq(blank.selector(), Variable("ACME_PROFILES"))
  assert_eq(blank.controls(), [])
}

///|
test "groups retain group names and last duplicate occurrence with typed reasons" {
  let policy = @profiles.Policy::new() |> @profiles.includes(names(["metrics"])) |> @profiles.group(@config.ProfileName::parse("production"), names(["postgres", "metrics"]))
  let result = @profiles.resolve(policy, selected(["production", "postgres"]))
  assert_eq(active(result), ["production", "metrics", "postgres"])
  assert_eq(result.reasons(), [Root(@config.ProfileName::parse("production"), Discovery), GroupMember(@config.ProfileName::parse("metrics"), @config.ProfileName::parse("production"), Policy), Root(@config.ProfileName::parse("postgres"), Discovery)])
  let replacement = controls({ "profiles": { "groups": { "production": ["marker"] } } })
  assert_eq(active(@profiles.resolve(policy, selected(["production"]), controls=replacement)), ["metrics", "production", "marker"])
  assert_eq(active(@profiles.resolve(policy, selected(["unknown", "unknown"]))), ["metrics", "unknown"])
  let empty = policy |> @profiles.group(@config.ProfileName::parse("empty"), names([]))
  assert_eq(active(@profiles.resolve(empty, selected(["empty"]))), ["metrics", "empty"])
}

///|
test "diamond expansion is stable independent of group map order" {
  let first = controls({ "profiles": { "groups": { "root": ["left", "right"], "left": ["shared"], "right": ["shared"] } } })
  let second = controls({ "profiles": { "groups": { "right": ["shared"], "left": ["shared"], "root": ["left", "right"] } } })
  let a = @profiles.resolve(@profiles.Policy::new(), selected(["root"]), controls=first)
  let b = @profiles.resolve(@profiles.Policy::new(), selected(["root"]), controls=second)
  assert_eq(active(a), ["root", "left", "right", "shared"])
  assert_eq(a, b)
  assert_true(a.controls().length() >= 5)
}

///|
test "inactive cycles retain a closed path and literal control origin" {
  let cyclic = controls({ "profiles": { "groups": { "b": ["a"], "a": ["b"] } } })
  try { ignore(@profiles.resolve(@profiles.Policy::new(), selected(["metrics"]), controls=cyclic)) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), Cycle)
      assert_eq(failure.cycle(), names(["a", "b", "a"]))
      assert_eq(failure.origin(), Control(origin(), @config.KeyPath::parse("profiles.groups.a")))
    }
    error => raise error
  } noraise { _ => fail("expected the inactive cycle") }
  let direct = @profiles.Policy::new() |> @profiles.group(@config.ProfileName::parse("a"), names(["a"]))
  expect_rule(() => ignore(@profiles.resolve(direct, Unspecified)), Cycle)
  assert_eq(active(@profiles.resolve(direct, Disabled)), [])
}

///|
test "literal base selectors are parsed even when a higher selector wins" {
  let bad = controls({ "profiles": { "active": 42 } })
  expect_rule(() => ignore(@profiles.resolve(@profiles.Policy::new(), selected(["metrics"]), controls=bad)), ExpectedList)
  assert_true(@profiles.resolve(@profiles.Policy::new(), Unspecified, variable=("ACME_PROFILES", ""), controls=bad).disabled())
  // A higher explicit selector suppresses parsing of the selector variable.
  assert_eq(active(@profiles.resolve(@profiles.Policy::new(), selected(["metrics"]), variable=("ACME_PROFILES", "BAD"))), ["metrics"])
}

///|
test "control shape errors carry their exact key and file source" {
  let cases : Array[(Json, @config.ProfileRule, String)] = [
    ({ "profiles": 42 }, ExpectedTable, "profiles"),
    ({ "profiles": { "unknown": [] } }, UnknownField, "profiles.unknown"),
    ({ "profiles": { "active": false } }, ExpectedList, "profiles.active"),
    ({ "profiles": { "active": [1] } }, ExpectedString, "profiles.active"),
    ({ "profiles": { "groups": [] } }, ExpectedTable, "profiles.groups"),
    ({ "profiles": { "groups": { "group": 42 } } }, ExpectedList, "profiles.groups.group"),
    ({ "profiles": { "groups": { "Group": [] } } }, NameStart, "profiles.groups.Group"),
    ({ "profiles": { "default": ["${SECRET}"] } }, NonLiteral, "profiles.default"),
    ({ "profiles": { "include": [{ "env": "SECRET" }] } }, ExpectedString, "profiles.include"),
  ]
  for item in cases {
    try { ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, controls=controls(item.0))) } catch {
      @config.Profile(failure~) => {
        assert_eq(failure.rule(), item.1)
        assert_eq(failure.origin(), Control(origin(), @config.KeyPath::parse(item.2)))
      }
      error => raise error
    } noraise { _ => fail("expected a literal control shape failure") }
  }
}

///|
fn chain(count : Int) -> @profiles.Policy raise @config.ConfigError {
  let mut policy = @profiles.Policy::new()
  for index in 0..<count {
    let children = if index + 1 < count { names(["g\{index + 1}"]) } else { names(["leaf"]) }
    policy = policy |> @profiles.group(@config.ProfileName::parse("g\{index}"), children)
  }
  policy
}

///|
test "group and member count boundaries reject the first excess" {
  let mut policy = @profiles.Policy::new()
  for index in 0..<64 { policy = policy |> @profiles.group(@config.ProfileName::parse("g\{index}"), names([])) }
  assert_eq(active(@profiles.resolve(policy, selected(["g0"]))), ["g0"])
  expect_rule(() => ignore(policy |> @profiles.group(@config.ProfileName::parse("extra"), names([]))), GroupLimit(65))
  let children = names(Array::makei(64, index => "child\{index}"))
  let exact = @profiles.Policy::new() |> @profiles.group(@config.ProfileName::parse("root"), children)
  assert_eq(active(@profiles.resolve(exact, selected(["root"]))).length(), 65)
  expect_rule(() => ignore(@profiles.Policy::new() |> @profiles.group(@config.ProfileName::parse("root"), names(Array::makei(65, index => "child\{index}")))), MemberLimit(65))
}

///|
test "group depth counts definitions and validates inactive chains" {
  assert_eq(active(@profiles.resolve(chain(32), selected(["g0"]))).length(), 33)
  expect_rule(() => ignore(@profiles.resolve(chain(33), selected(["marker"]))), DepthLimit(33))
}

///|
test "active count allows exactly 128 distinct names and rejects 129" {
  let exact = names(Array::makei(128, index => "p\{index}"))
  assert_eq(active(@profiles.resolve(@profiles.Policy::new(), Selected(exact))).length(), 128)
  let excess = names(Array::makei(129, index => "p\{index}"))
  expect_rule(() => ignore(@profiles.resolve(@profiles.Policy::new(), Selected(excess))), ActiveLimit(129))
}

///|
test "shared subgroups bound work despite billions of expansion paths" {
  let mut policy = @profiles.Policy::new() |> @profiles.group(@config.ProfileName::parse("g0"), names(["leaf"]))
  for index in 1..<32 {
    policy = policy |> @profiles.group(@config.ProfileName::parse("g\{index}"), names(["g\{index - 1}", "g\{index - 1}"]))
  }
  let resolved = @profiles.resolve(policy, selected(["g31"]))
  assert_eq(active(resolved).length(), 33)
  assert_eq(active(resolved).last(), Some("leaf"))
}

///|
test "policies and resolution collections do not share mutable public state" {
  let original = @profiles.Policy::new()
  let changed = original |> @profiles.fallback(names(["metrics"])) |> @profiles.includes(names(["common"]))
  assert_eq(active(@profiles.resolve(original, Unspecified)), [])
  let first = @profiles.resolve(changed, Unspecified)
  first.active().names().clear()
  first.roots().names().clear()
  first.reasons().clear()
  first.controls().clear()
  assert_eq(active(@profiles.resolve(changed, Unspecified)), ["common", "metrics"])
  assert_eq(first.reasons().length(), 2)
}

///|
test "file group count and member limits use the control origin" {
  let definitions = Array::makei(64, index => ("g\{index}", @config.list([])))
  let exact = @config.fields([("profiles", @config.fields([("groups", @config.fields(definitions))]))])
  assert_eq(active(@profiles.resolve(@profiles.Policy::new(), Unspecified, controls=(exact, origin()))), [])
  let excess = @config.fields([("profiles", @config.fields([("groups", @config.fields([..definitions, ("extra", @config.list([]))]))]))])
  expect_rule(() => ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, controls=(excess, origin()))), GroupLimit(65))
  let members = @config.list(Array::makei(64, index => @config.string("child\{index}")))
  let file = @config.fields([("profiles", @config.fields([("groups", @config.fields([("root", members)]))]))])
  assert_eq(active(@profiles.resolve(@profiles.Policy::new(), selected(["root"]), controls=(file, origin()))).length(), 65)
  let members = @config.list(Array::makei(65, index => @config.string("child\{index}")))
  let file = @config.fields([("profiles", @config.fields([("groups", @config.fields([("root", members)]))]))])
  try { ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, controls=(file, origin()))) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), MemberLimit(65))
      assert_eq(failure.origin(), Control(origin(), @config.KeyPath::parse("profiles.groups.root")))
    }
    error => raise error
  } noraise { _ => fail("expected the file member limit") }
}

///|
test "base groups replace policy groups before effective graph validation" {
  let cyclic_policy = @profiles.Policy::new() |> @profiles.group(@config.ProfileName::parse("root"), names(["root"]))
  let file = controls({ "profiles": { "groups": { "root": ["metrics"] } } })
  assert_eq(active(@profiles.resolve(cyclic_policy, selected(["root"]), controls=file)), ["root", "metrics"])
  let mut many = @profiles.Policy::new()
  for index in 0..<64 { many = many |> @profiles.group(@config.ProfileName::parse("g\{index}"), names([])) }
  let replaced = controls({ "profiles": { "groups": { "g0": ["metrics"] } } })
  assert_eq(active(@profiles.resolve(many, selected(["g0"]), controls=replaced)), ["g0", "metrics"])
  let additional = controls({ "profiles": { "groups": { "extra": [] } } })
  expect_rule(() => ignore(@profiles.resolve(many, Unspecified, controls=additional)), GroupLimit(65))
}

///|
test "variable and active-limit failures retain winning selector identity" {
  try { ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, variable=("ACME_PROFILES", "metrics,,tracing"))) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), EmptyElement)
      assert_eq(failure.origin(), Variable("ACME_PROFILES"))
    }
    error => raise error
  } noraise { _ => fail("expected invalid variable list") }
  let excessive = Array::makei(129, index => "p\{index}").join(",")
  try { ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, variable=("ACME_PROFILES", excessive))) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), ActiveLimit(129))
      assert_eq(failure.origin(), Variable("ACME_PROFILES"))
    }
    error => raise error
  } noraise { _ => fail("expected variable active-count limit") }
}

///|
test "active-limit errors identify the authoritative base selector control" {
  let excessive = @config.list(Array::makei(129, index => @config.string("p\{index}")))
  for selector in ["active", "default"] {
    let file = @config.fields([("profiles", @config.fields([(selector, excessive)]))])
    try { ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, controls=(file, origin()))) } catch {
      @config.Profile(failure~) => {
        assert_eq(failure.rule(), ActiveLimit(129))
        assert_eq(failure.origin(), Control(origin(), @config.KeyPath::parse("profiles.\{selector}")))
      }
      error => raise error
    } noraise { _ => fail("expected base active-count limit") }
  }
}

///|
test "active-limit errors retain include and group control origins with fallback selection" {
  let excessive = @config.list(Array::makei(129, index => @config.string("p\{index}")))
  let included = @config.fields([("profiles", @config.fields([("include", excessive)]))])
  try { ignore(@profiles.resolve(@profiles.Policy::new(), Unspecified, controls=(included, origin()))) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), ActiveLimit(129))
      assert_eq(failure.origin(), Control(origin(), @config.KeyPath::parse("profiles.include")))
    }
    error => raise error
  } noraise { _ => fail("expected include active-count limit") }
  let groups = @config.fields([
    ("left", @config.list(Array::makei(64, index => @config.string("p\{index}")))),
    ("right", @config.list(Array::makei(64, index => @config.string("q\{index}")))),
  ])
  let file = @config.fields([("profiles", @config.fields([("groups", groups)]))])
  let policy = @profiles.Policy::new() |> @profiles.fallback(names(["left", "right"]))
  try { ignore(@profiles.resolve(policy, Unspecified, controls=(file, origin()))) } catch {
    @config.Profile(failure~) => {
      assert_eq(failure.rule(), ActiveLimit(130))
      assert_eq(failure.origin(), Control(origin(), @config.KeyPath::parse("profiles.groups.right")))
    }
    error => raise error
  } noraise { _ => fail("expected group active-count limit") }
}

///|
test "prepared selection preserves variable origin without reparsing" {
  let prepared = @profiles.SelectionInput::new(Unspecified, variable=("ACME_PROFILES", "metrics"))
  assert_false(prepared.disabled())
  let result = @profiles.resolve_input(@profiles.Policy::new(), prepared)
  assert_eq(active(result), ["metrics"])
  assert_eq(result.selector(), Variable("ACME_PROFILES"))
  assert_true(@profiles.SelectionInput::new(Unspecified, variable=("ACME_PROFILES", "")).disabled())
  assert_true(@profiles.SelectionInput::new(Disabled, variable=("ACME_PROFILES", "BAD")).disabled())
}
