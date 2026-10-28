///|
fn profile_host(argv : Array[String]) -> HostBuilder[String] raise {
  builder(@lander_core.AppName::parse("acme"), argv,
    env_vars=(Map([]) : Map[String, String]),
    working_dir=@lander_core.AbsolutePath::parse("/w"))
  |> command(name => @argparse.Command(name,
    options=[@hosting_argparse.profiles_option()],
    flags=[@hosting_argparse.no_profiles_flag()],
    subcommands=[@argparse.Command("build")]))
  |> configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format()))
}

///|
test "profile CLI selects one file and the factory and later context share its resolution" {
  let metrics = @config.ProfileName::parse("metrics")
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/w"), [
      { name: "acme.toml", kind: File },
      { name: "acme.profile.metrics.toml", kind: File },
    ])
    .with_file(p("/w/acme.toml"), "mode = \"base\"")
    .with_file(p("/w/acme.profile.metrics.toml"), "mode = \"metrics\"")
  let factory_state = Ref(@config.ProfileState::Off)
  let host = profile_host(["build", "--profiles", "metrics"])
    |> app_dirs() |> profiles(@profiles.Policy::new()) |> files(tree)
    |> build(ctx => {
      factory_state.val = ctx.config.profiles()
      assert_true(ctx.config.profiles().contains(metrics))
      @config.get_text(ctx.config, "mode")
    })
  let loaded = injected_run(host)
  assert_eq(loaded.context.services, "metrics")
  assert_eq(loaded.context.config.profiles(), factory_state.val)
  assert_true(loaded.context.config.reports().iter().any(report =>
    report.kind is File(ProfileFile(name)) && name == metrics &&
    report.priority == 380 && report.status is Loaded))
}

///|
test "profile CLI parsing retains repeated order and rejects invalid input while profiles are off" {
  let host = profile_host(["--profiles", "postgres, metrics", "build", "--profiles", "tracing"])
    |> build(_ => "")
  let parsed = parse_test_arguments(host)
  assert_eq(parsed.discovery_options.profiles, @config.Selected(@config.ProfileNames::new([
    @config.ProfileName::parse("postgres"), @config.ProfileName::parse("metrics"),
    @config.ProfileName::parse("tracing"),
  ])))
  for argv in [["--profiles="], ["--profiles", "postgres,,metrics"],
    ["--profiles", "Metrics"], ["--profiles", "metrics", "--no-profiles"]] {
    let factory_calls = Ref(0)
    let host = profile_host(argv) |> build(_ => { factory_calls.val += 1; "" })
    try {
      ignore(injected_run(host))
      fail("expected invalid profile arguments")
    } catch {
      UsageError(_) as error => assert_eq(outcome(error).exit_code().to_int(), 2)
      error => raise error
    }
    assert_eq(factory_calls.val, 0)
  }
}

///|
test "profile help and version stop before configuration callbacks and factory" {
  for argv in [["--profiles", "metrics", "--help"], ["--profiles", "metrics", "--version"]] {
    let calls = Ref(0)
    let host = profile_host(argv)
      |> command(name => @argparse.Command(name, version="1.2.3",
        options=[@hosting_argparse.profiles_option()], flags=[@hosting_argparse.no_profiles_flag()]))
      |> configure(s => { calls.val += 1; s })
      |> app_dirs() |> profiles(@profiles.Policy::new())
      |> build(_ => { calls.val += 1; "" })
    try {
      ignore(configuration_inputs(host))
      fail("expected a display request")
    } catch {
      DisplayRequested(_) => ()
      error => raise error
    }
    assert_eq(calls.val, 0)
  }
}

///|
test "profiles-off flags add a note and keep the ordinary application variable" {
  for argv in [["--profiles", "metrics"], ["--no-profiles"]] {
    let loaded = profile_host(argv)
      |> env_vars({ "ACME_PROFILES": "application-data" })
      |> build(_ => "") |> injected_run
    assert_eq(loaded.context.config.profiles(), Off)
    assert_eq(@config.get_text(loaded.context.config, "profiles"), "application-data")
    assert_true(loaded.context.config.warnings().iter().any(warning =>
      warning is Note(message~, ..) && message.contains("profiles")))
    assert_false(loaded.context.config.reports().iter().any(report => report.kind is File(_)))
  }
}

///|
test "an enabled bare profile policy adds no file discovery and has no implicit default" {
  let config = profile_host([]) |> profiles(@profiles.Policy::new())
    |> build(_ => "") |> injected_run |> (run => run.context.config)
  guard config.profiles() is Resolved(resolution) else { fail("expected an enabled resolution") }
  assert_eq(resolution.active().names(), [])
  assert_false(resolution.disabled())
  assert_true(config.reports().iter().all(report => report.path is None && report.candidates.is_empty()))
}

///|
test "host prefix controls selector reservation and profile snapshots remain independent" {
  let metrics = @config.ProfileName::parse("metrics")
  let tracing = @config.ProfileName::parse("tracing")
  let variables = { "APP_PROFILES": "metrics", "ACME_PROFILES": "unused" }
  let base = profile_host([]) |> env_prefix(@lander_core.EnvPrefix::parse("APP"))
    |> profiles(@profiles.Policy::new()) |> env_vars(variables)
  variables["APP_PROFILES"] = "tracing"
  let first = base |> build(_ => "") |> injected_run
  let second = base |> env_vars(variables) |> build(_ => "") |> injected_run
  assert_true(first.context.config.profiles().contains(metrics))
  assert_false(first.context.config.profiles().contains(tracing))
  assert_true(second.context.config.profiles().contains(tracing))
  assert_false(second.context.config.profiles().contains(metrics))
  assert_true(first.context.config.get(@config.KeyPath::parse("profiles")) is None)
  assert_eq(base |> build(_ => "") |> injected_run |> (run => run.context.config.profiles()),
    first.context.config.profiles())
}

///|
test "explicit disable skips invalid controls while environment remains selected" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/w"), [{ name: "acme.toml", kind: File }, { name: "acme.Production.toml", kind: File }])
    .with_file(p("/w/acme.toml"), "profiles.active = 42\nmode = \"base\"")
    .with_file(p("/w/acme.Production.toml"), "mode = \"environment\"")
  let loaded = profile_host(["--no-profiles"])
    |> app_dirs() |> profiles(@profiles.Policy::new())
    |> default_environment(@conventions.EnvironmentName::parse("Production"))
    |> files(tree) |> build(ctx => @config.get_text(ctx.config, "mode")) |> injected_run
  assert_eq(loaded.context.services, "environment")
  assert_true(loaded.context.environment.is_production())
  guard loaded.context.config.profiles() is Resolved(resolution) else { fail("expected disabled resolution") }
  assert_true(resolution.disabled())
  assert_eq(resolution.active().names(), [])
  assert_true(loaded.context.config.get(@config.KeyPath::parse("profiles")) is None)
  assert_false(loaded.context.config.reports().iter().any(report => report.kind is File(ProfileFile(_))))
}

///|
test "profile processing rejects generic control overrides before the factory" {
  let calls = Ref(0)
  let host = profile_host(["--setting", "metrics"])
    |> profiles(@profiles.Policy::new())
    |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("setting")]),
      mappings=[mapping("setting", "profiles.active")])
    |> build(_ => { calls.val += 1; "" })
  try {
    ignore(injected_run(host))
    fail("expected forbidden profile override")
  } catch {
    @config.Profile(failure~) as error => {
      assert_eq(failure.rule(), ForbiddenLocation)
      assert_eq(outcome(error).exit_code().to_int(), 2)
    }
    error => raise error
  }
  assert_eq(calls.val, 0)
}

///|
test "custom configure profile providers keep explicit options and reserve their selector" {
  let metrics = @config.ProfileName::parse("metrics")
  let config = profile_host([])
    |> env_vars({ "ACME_PROFILES": "metrics" }) |> reserve_env(["ACME_PROFILES"])
    |> configure(s => s |> @conventions.add(
      @conventions.base("acme") |> @conventions.profiles(@profiles.Policy::new()),
      options=@conventions.DiscoveryOptions::new(profiles=Selected(@config.ProfileNames::new([metrics])))))
    |> build(_ => "") |> injected_run |> (run => run.context.config)
  assert_true(config.profiles().contains(metrics))
  assert_true(config.get(@config.KeyPath::parse("profiles")) is None)
}

///|
test "a host parses its command once per configuration run" {
  let parses = Ref(0)
  let host = profile_host(["--profiles", "metrics"])
    |> profiles(@profiles.Policy::new())
    |> command(name => {
      parses.val += 1
      @argparse.Command(name, options=[@hosting_argparse.profiles_option()], flags=[@hosting_argparse.no_profiles_flag()])
    }) |> build(_ => "")
  ignore(injected_run(host))
  assert_eq(parses.val, 1)
  ignore(injected_run(host))
  assert_eq(parses.val, 2)
}
