///|
async test "profile disk requests reach the factory hooks and command with one loaded resolution" {
  let metrics = @config.ProfileName::parse("metrics")
  let seen = []
  let state = Ref(@config.ProfileState::Off)
  let result = configured_host(["--profiles", "metrics"])
    |> @hosting.profiles(@profiles.Policy::new())
    |> @hosting.service("profile-service", start=ctx => {
      assert_eq(ctx.config.profiles(), state.val)
      assert_true(ctx.config.profiles().contains(metrics))
      seen.push("hook")
    })
    |> @hosting.build(ctx => {
      state.val = ctx.config.profiles()
      assert_true(state.val.contains(metrics))
      seen.push("factory")
      @config.get_text(ctx.config, "profile_only")
    })
    |> @hosting.run(ctx => {
      assert_eq(ctx.services, "metrics")
      assert_eq(ctx.config.profiles(), state.val)
      seen.push("command")
    })
  assert_eq(result.exit_code().to_int(), 0,
    msg=result.failures().map(error => @debug.to_string(error)).join("\n"))
  assert_eq(seen, ["factory", "hook", "command"])
}

///|
async test "profile usage failures end native and js runs before configuration or services" {
  for argv in [["--profiles="], ["--profiles", "postgres,,metrics"],
    ["--profiles", "metrics", "--no-profiles"]] {
    let calls = Ref(0)
    let result = configured_host(argv)
      |> @hosting.profiles(@profiles.Policy::new())
      |> @hosting.configure(s => { calls.val += 1; s })
      |> @hosting.service("database", start=_ => calls.val += 1)
      |> @hosting.build(_ => calls.val += 1)
      |> @hosting.run(_ => calls.val += 1)
    assert_eq(result.exit_code().to_int(), 2)
    assert_eq(calls.val, 0)
    assert_true(result.failures() is [@hosting.UsageError(_)])
  }
}

///|
async test "separate host run snapshots never retain earlier active profiles" {
  let metrics = @config.ProfileName::parse("metrics")
  let tracing = @config.ProfileName::parse("tracing")
  let base : @hosting.HostBuilder[@config.ProfileState] = configured_host([])
    |> @hosting.profiles(@profiles.Policy::new())
  let seen = []
  for (variables, selected, absent) in [
    ({ "ACME_PROFILES": "metrics" }, metrics, tracing),
    ({ "ACME_PROFILES": "tracing" }, tracing, metrics),
  ] {
    let result = base |> @hosting.env_vars(variables)
      |> @hosting.build(ctx => ctx.config.profiles())
      |> @hosting.run(ctx => {
        assert_eq(ctx.services, ctx.config.profiles())
        assert_true(ctx.services.contains(selected))
        assert_false(ctx.services.contains(absent))
        seen.push(selected)
      })
    assert_eq(result.exit_code().to_int(), 0,
      msg=result.failures().map(error => @debug.to_string(error)).join("\n"))
  }
  assert_eq(seen, [metrics, tracing])
}

///|
async test "invalid file controls use configuration exit policy and disable skips their interpretation" {
  let calls = Ref(0)
  let failed = configured_host([], directory="profiles-invalid")
    |> @hosting.profiles(@profiles.Policy::new())
    |> @hosting.service("database", start=_ => calls.val += 1)
    |> @hosting.build(_ => calls.val += 1) |> @hosting.run(_ => calls.val += 1)
  assert_eq(failed.exit_code().to_int(), 2)
  assert_eq(calls.val, 0)
  guard failed.failures() is [@config.Profile(failure~)] else {
    fail("expected a typed profile failure")
  }
  assert_eq(failure.rule(), ExpectedList)
  let disabled = configured_host(["--no-profiles"], directory="profiles-invalid")
    |> @hosting.profiles(@profiles.Policy::new())
    |> @hosting.build(ctx => {
      assert_true(ctx.config.get(@config.KeyPath::parse("profiles")) is None)
      @config.get_text(ctx.config, "mode")
    }) |> @hosting.run(ctx => assert_eq(ctx.services, "base"))
  assert_eq(disabled.exit_code().to_int(), 0)
}
