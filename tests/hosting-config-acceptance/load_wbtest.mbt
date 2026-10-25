///|
fn fixture(path : String) -> @lander_core.AbsolutePath raise {
  // moon test runs from this unpublished module root.
  @lander_core.AbsolutePath::parse(@env.current_dir().unwrap() + "/hosting-config-acceptance/fixtures/" + path)
}

///|
fn[S] configured_host(argv : Array[String], directory? : String = "workspace") -> @hosting.HostBuilder[S] raise {
  @hosting.builder(@lander_core.AppName::parse("acme"), argv,
    env_vars=(Map([]) : Map[String, String]), working_dir=fixture(directory))
  |> @hosting_argparse.command(name => @argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option()],
    flags=[@hosting_argparse.isolated_flag()]))
  // A fixed discovery platform makes the HOME candidate assertion portable.
  |> @hosting.configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format()))
  |> @hosting.app_dirs()
  |> @hosting.error_report((_, _) => ())
}

///|
async test "project selector chooses a path before a conflicting project name through disk load" {
  for (selector, selected) in [("packages/a", "a"), ("packages/a/", "a"), ("packages/c", "c")] {
    let calls = Ref(0)
    let result = configured_host(["--project", selector])
      |> @hosting.conventions(c => c |> @conventions.workspace())
      |> @hosting.build(b => { calls.val += 1; @config.get_text(b.config, "selected") })
      |> @hosting.run(ctx => assert_eq(ctx.services, selected))
    assert_eq(result.exit_code().to_int(), 0,
      msg="project \{selector}: " + result.failures().map(error => error.to_string()).join("\n"))
    assert_eq(calls.val, 1)
  }
}

///|
async test "ambiguous project name gives config code 2 before factory and hooks" {
  let calls = Ref(0)
  let result = configured_host(["--project", "duplicate"])
    |> @hosting.conventions(c => c |> @conventions.workspace())
    |> @hosting.service("must-not-start", start=_ => calls.val += 1)
    |> @hosting.build(_ => calls.val += 1)
    |> @hosting.run(_ => calls.val += 1)
  assert_eq(result.exit_code().to_int(), 2,
    msg=result.failures().map(error => error.to_string()).join("\n"))
  assert_eq(calls.val, 0)
  guard result.failures() is [@config.AmbiguousProject(selector~, matches~)] else { fail("expected ambiguous project") }
  assert_eq(selector, "duplicate")
  assert_eq(matches, ["packages/a", "packages/b"])
}

///|
async test "Staging flag beats variable and starting default and loads exact-case environment file" {
  let result = configured_host(["--environment", "Staging"])
    |> @hosting.env_vars({ "ACME_ENVIRONMENT": "Production" })
    |> @hosting.default_environment(@conventions.EnvironmentName::parse("Development"))
    |> @hosting.build(b => {
      assert_true(b.environment.is_staging())
      @config.get_text(b.config, "environment_file")
    })
    |> @hosting.run(ctx => {
      assert_eq(ctx.services, "Staging")
      assert_true(ctx.environment.is_staging())
      assert_true(ctx.config.reports().iter().any(r => r.path == Some(fixture("workspace/acme.Staging.toml").to_string()) && r.status is Loaded))
    })
  assert_eq(result.exit_code().to_int(), 0)
}

///|
async test "host app_dirs receives config and isolated flags while files tree is ignored on native and js" {
  let result = configured_host(["--config", "../alternate/acme.toml", "--isolated"])
    |> @hosting.files(@config.FileTree::new(complete=true)
      .with_file(fixture("alternate/acme.toml").to_string(), "from_directory = \"injected\""))
    |> @hosting.build(b => {
      assert_eq(@config.get_text(b.config, "from_directory"), "alternate")
      assert_true(b.config.reports().iter().any(r => r.kind is File(System) && r.status is Skipped))
    })
    |> @hosting.run(_ => ())
  assert_eq(result.exit_code().to_int(), 0)
}

///|
async test "malformed or missing explicit file is configuration code 2 before any factory or hook" {
  for path in ["../bad.toml", "../absent.toml"] {
    let calls = Ref(0)
    let result = configured_host(["--config", path])
      |> @hosting.service("never", start=_ => calls.val += 1)
      |> @hosting.build(_ => calls.val += 1)
      |> @hosting.run(_ => calls.val += 1)
    assert_eq(result.exit_code().to_int(), 2)
    assert_eq(calls.val, 0)
    assert_true(result.failures()[0] is @config.ConfigError::_)
  }
}

///|
async test "one factory and same mutable services config variables and directory reach every hook and command" {
  let calls = Ref(0)
  let services = Ref(0)
  let vars = { "ACME_ENVIRONMENT": "Staging", "ACME_LOG__FORMAT": "json", "HOME": "/home/test" }
  let check : @hosting.Hook[Ref[Int]] = ctx => {
    assert_eq(ctx.services.val, services.val)
    assert_eq(ctx.env_vars.get("HOME"), Some("/home/test"))
    assert_eq(ctx.env_vars.get("ACME_LOG__FORMAT"), Some("json"))
    assert_eq(ctx.env_vars.length(), vars.length())
    assert_eq(ctx.working_dir, fixture("workspace"))
    assert_true(ctx.environment.is_staging())
    assert_eq(@config.get_text(ctx.config, "log.format"), "json")
    assert_eq((@config.bind(ctx.config, "file_only") : Bool), true)
    assert_true(ctx.config.reports().iter().any(r => r.candidates.contains("/home/test/.acme/acme.toml")))
    ctx.services.val += 1
  }
  let result = configured_host([])
    |> @hosting.env_vars(vars)
    |> @hosting.default_environment(@conventions.EnvironmentName::parse("Production"))
    |> @hosting.service("a", starting=check, start=check, started=check, stopping=check, stop=check, stopped=check)
    |> @hosting.service("b", starting=check, start=check, started=check, stopping=check, stop=check, stopped=check)
    |> @hosting.build(b => {
      calls.val += 1
      assert_eq(services.val, 0)
      assert_eq(b.env_vars.get("HOME"), Some("/home/test"))
      assert_eq(b.working_dir, fixture("workspace"))
      assert_true(b.environment.is_staging())
      assert_eq(@config.get_text(b.config, "log.format"), "json")
      services
    })
    |> @hosting.run(ctx => {
      ctx.lifetime.on_stopping(() => assert_eq(services.val, 7) catch { _ => abort("same services at stopping event") })
      check(ctx)
    })
  assert_eq(result.exit_code().to_int(), 0)
  assert_eq(calls.val, 1)
  assert_eq(services.val, 13)
}

///|
async test "later directory starts real discovery there and later variables replace the starting set" {
  let result = configured_host([])
    |> @hosting.env_vars({ "ACME_A": "1" })
    |> @hosting.working_dir(fixture("alternate"))
    |> @hosting.env_vars({ "ACME_B": "2" })
    |> @hosting.build(b => {
      assert_eq(b.working_dir, fixture("alternate"))
      assert_eq(b.env_vars.length(), 1)
      assert_eq(b.env_vars.get("ACME_B"), Some("2"))
      assert_true(b.config.get(@config.KeyPath::parse("a")) is None)
      assert_eq((@config.bind(b.config, "b") : Int), 2)
      @config.get_text(b.config, "from_directory")
    }) |> @hosting.run(ctx => assert_eq(ctx.services, "alternate"))
  assert_eq(result.exit_code().to_int(), 0)
}

///|
async test "named timeout key overrides builder through disk load and bounds shutdown" {
  let log = []
  let result = configured_host(["--config", "../timeout.toml"])
    |> @hosting.shutdown_timeout(@lander_core.TimeLimit::seconds(30))
    |> @hosting.shutdown_timeout_key(@config.KeyPath::parse("app.shutdown_timeout"))
    |> @hosting.service("a", stop=_ => log.push("must not stop"))
    |> @hosting.service("b", stop=_ => { defer log.push("cancelled"); @async.sleep(10000) })
    |> @hosting.build(_ => log.push("factory"))
    |> @hosting.run(ctx => ctx.lifetime.on_stopped(() => log.push("stopped")))
  assert_eq(result.exit_code().to_int(), 1)
  assert_eq(log, ["factory", "cancelled", "stopped"])
  guard result.failures() is [@hosting.ShutdownTimedOut(limit)] else { fail("expected timeout") }
  assert_eq(limit.to_millis(), 100)
}

///|
async test "invalid named timeout value is a config failure before factory and hooks" {
  let calls = Ref(0)
  let result = configured_host(["--config", "../bad-timeout.toml"])
    |> @hosting.shutdown_timeout_key(@config.KeyPath::parse("app.shutdown_timeout"))
    |> @hosting.service("a", start=_ => calls.val += 1)
    |> @hosting.build(_ => calls.val += 1) |> @hosting.run(_ => calls.val += 1)
  assert_eq(result.exit_code().to_int(), 2)
  assert_eq(calls.val, 0)
  assert_true(result.failures()[0] is @config.Decode(_))
}

///|
async test "omitted settings use the process snapshot and discover from its actual working directory" {
  let previous = @env.get_env_var("ACME_LOG__FORMAT")
  @env.set_env_var("ACME_LOG__FORMAT", "json")
  defer {
    match previous {
      Some(value) => @env.set_env_var("ACME_LOG__FORMAT", value)
      None => @env.unset_env_var("ACME_LOG__FORMAT")
    }
  }
  let cwd = @lander_core.AbsolutePath::parse(@env.current_dir().unwrap())
  // The module manifest is a real discoverable file in the process directory.
  // This format lets the fixture use it without modifying the directory.
  let manifest : @config.Format = { name: "manifest", extensions: ["mod"], parse: (_, path) =>
    @config.fields([("manifest", @config.string(path)), ("log", @config.fields([("format", @config.string("text"))]))]) }
  let expected = @env.get_env_vars()
  let result = @hosting.builder(@lander_core.AppName::parse("acme"), [])
    |> @hosting.configure(s => s |> @config.format(manifest))
    |> @hosting.conventions(_ => @conventions.app_dirs("moon") |> @conventions.boundary(cwd.to_string()))
    |> @hosting.build(b => {
      assert_eq(b.working_dir, cwd)
      assert_eq(b.env_vars.get("ACME_LOG__FORMAT"), expected.get("ACME_LOG__FORMAT"))
      assert_eq(b.env_vars.length(), expected.length())
      assert_eq(@config.get_text(b.config, "log.format"), "json")
      assert_eq(@config.get_text(b.config, "manifest"), cwd.to_string() + "/moon.mod")
    }) |> @hosting.run(ctx => assert_eq(ctx.working_dir, cwd))
  assert_eq(result.exit_code().to_int(), 0)
}

///|
async test "explicit disk settings give the same complete configuration and reports as an injected tree" {
  let vars = { "ACME_LOG__FORMAT": "json", "HOME": "/home/test" }
  let dir = fixture("workspace").to_string()
  let tree = @config.FileTree::new(complete=true)
    .with_listing(dir, [{ name: "acme.toml", kind: File }, { name: "acme.Staging.toml", kind: File }, { name: "packages", kind: Directory }])
    .with_file(dir + "/acme.toml", "workspace.members = [\"packages/*\"]\nlog.format = \"text\"\nfile_only = true\n")
    .with_file(dir + "/acme.Staging.toml", "environment_file = \"Staging\"\n")
  let sources = @config.builder() |> @config.env_vars(vars) |> @config.working_dir(dir)
    |> @config.platform(Linux) |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
    |> @config.env(prefix="ACME", reserved=["ACME_HOME", "ACME_ENVIRONMENT"])
  guard @config.load(sources, tree) is Done(injected) else { fail("complete tree must load") }
  let result = configured_host([]) |> @hosting.env_vars(vars)
    |> @hosting.build(b => {
      assert_eq(b.config.value(), injected.value())
      assert_eq(b.config.reports(), injected.reports())
    }) |> @hosting.run(_ => ())
  assert_eq(result.exit_code().to_int(), 0)
}

///|
async test "bad arguments and invalid environment stop before application configuration callbacks" {
  for argv in [["--unknown"], ["--environment", "../Production"]] {
    let calls = Ref(0)
    let result = configured_host(argv)
      |> @hosting.configure(s => { calls.val += 1; s })
      |> @hosting.service("a", start=_ => calls.val += 1)
      |> @hosting.build(_ => calls.val += 1) |> @hosting.run(_ => calls.val += 1)
    assert_eq(result.exit_code().to_int(), 2)
    assert_eq(calls.val, 0)
  }
}
