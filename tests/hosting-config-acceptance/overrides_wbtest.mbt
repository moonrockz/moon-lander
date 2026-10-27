///|
fn[S] overrides_host(argv : Array[String], directory? : String = "workspace") -> @hosting.HostBuilder[S] raise {
  let root = fixture(directory).to_string()
  configured_host(argv, directory~)
  // Bound discovery to the fixture, including on Windows CI (lander-4us.45).
  |> @hosting.conventions(c => c |> @conventions.boundary(root))
  |> @hosting_argparse.command(name => @hosting_argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option(),
      @hosting_argparse.OptionArg("log-format", long="log-format", default_values=["text"])],
    flags=[@hosting_argparse.isolated_flag(), @hosting_argparse.FlagArg("dry-run", long="dry-run")]),
    mappings=[@hosting_argparse.map(@hosting_argparse.OverrideOption::parse("log-format"), @config.KeyPath::parse("log.format"))])
}

///|
fn assert_json_override(config : @config.Config) -> Unit raise {
  assert_eq(@config.get_text(config, "log.format"), "json")
  guard config.origins(@config.KeyPath::parse("log.format")) is [origin] else {
    fail("expected one winning override origin")
  }
  assert_true(origin.kind is Overrides)
  assert_eq(origin.priority, 700)
  let reports = config.reports()
  let last = reports[reports.length() - 1]
  assert_true(last.kind is Overrides)
  assert_eq(last.priority, 700)
  assert_true(last.status is Loaded)
  let previous = reports[reports.length() - 2]
  assert_true(previous.kind is Environment)
  assert_eq(previous.priority, 600)
}

///|
async test "mapped argv beats a real file and environment before factory hook and command" {
  let seen = []
  let result = overrides_host(["--log-format", "json"])
    |> @hosting.env_vars({ "ACME_LOG__FORMAT": "yaml" })
    |> @hosting.service("observer", start=ctx => {
      assert_json_override(ctx.config)
      assert_eq(ctx.services, "json")
      seen.push("hook")
    })
    |> @hosting.build(b => {
      assert_json_override(b.config)
      assert_true((@config.bind(b.config, "file_only") : Bool))
      assert_true(b.config.reports().iter().any(r => r.path == Some(fixture("workspace/acme.toml").to_string()) && r.status is Loaded))
      seen.push("factory")
      @config.get_text(b.config, "log.format")
    })
    |> @hosting.run(ctx => {
      assert_json_override(ctx.config)
      assert_eq(ctx.services, "json")
      seen.push("command")
    })
  assert_eq(result.exit_code().to_int(), 0,
    msg=result.failures().map(error => @debug.to_string(error)).join("\n"))
  assert_eq(seen, ["factory", "hook", "command"])
}

///|
async test "argparse default text preserves json from a real file" {
  let seen = []
  let result = overrides_host([], directory="json")
    |> @hosting.service("observer", start=ctx => {
      assert_eq(@config.get_text(ctx.config, "log.format"), "json")
      assert_eq(ctx.services, "json")
      seen.push("hook")
    })
    |> @hosting.build(b => {
      assert_eq(b.args.values.get("log-format"), Some(["text"]))
      assert_true(b.args.sources.get("log-format") is Some(Default))
      guard b.config.origins(@config.KeyPath::parse("log.format")) is [origin] else {
        fail("expected the file origin")
      }
      assert_true(origin.kind is File(_))
      assert_eq(origin.location, Some(fixture("json/acme.toml").to_string()))
      seen.push("factory")
      @config.get_text(b.config, "log.format")
    })
    |> @hosting.run(ctx => {
      assert_eq(@config.get_text(ctx.config, "log.format"), "json")
      assert_eq(ctx.services, "json")
      seen.push("command")
    })
  assert_eq(result.exit_code().to_int(), 0,
    msg=result.failures().map(error => @debug.to_string(error)).join("\n"))
  assert_eq(seen, ["factory", "hook", "command"])
}

///|
async test "unmapped dry run and standard discovery flags never enter configuration" {
  let seen = []
  let check : @hosting.Hook[Unit] = ctx => {
    assert_true(ctx.args.flags.get("dry-run") is Some(true))
    assert_true(ctx.args.flags.get("isolated") is Some(true))
    assert_eq(ctx.args.values.get("environment"), Some(["Staging"]))
    assert_eq(ctx.args.values.get("config"), Some(["acme.toml"]))
    assert_eq(ctx.args.values.get("project"), Some(["packages/a"]))
    for key in ["dry-run", "dry_run", "environment", "config", "isolated", "project", "log-format"] {
      assert_true(ctx.config.get(@config.KeyPath::parse(key)) is None)
    }
    assert_json_override(ctx.config)
  }
  let result = overrides_host(["--log-format", "json", "--dry-run", "--environment", "Staging", "--config", "acme.toml", "--isolated", "--project", "packages/a"])
    |> @hosting.service("observer", start=ctx => { check(ctx); seen.push("hook") })
    |> @hosting.build(b => {
      for key in ["dry-run", "dry_run", "environment", "config", "isolated", "project", "log-format"] {
        assert_true(b.config.get(@config.KeyPath::parse(key)) is None)
      }
      assert_json_override(b.config)
      seen.push("factory")
    })
    |> @hosting.run(ctx => { check(ctx); seen.push("command") })
  assert_eq(result.exit_code().to_int(), 0,
    msg=result.failures().map(error => @debug.to_string(error)).join("\n"))
  assert_eq(seen, ["factory", "hook", "command"])
}

///|
priv suberror InvalidOverrideFormat {
  InvalidOverrideFormat(String)
}

///|
async test "custom mapping parse failure reports UsageError code 2 before configuration factory and hooks" {
  let calls = []
  let reports : Array[(String, Int)] = []
  let parsed = []
  let result = overrides_host(["--log-format", "invalid"])
    |> @hosting_argparse.command(name => @hosting_argparse.Command(name,
      options=[@hosting_argparse.OptionArg("log-format", long="log-format")]),
      mappings=[@hosting_argparse.map(@hosting_argparse.OverrideOption::parse("log-format"), @config.KeyPath::parse("log.format"), parse=text => {
        parsed.push(text)
        raise InvalidOverrideFormat(text)
      })])
    |> @hosting.error_report((error, code) => {
      guard error is @hosting.UsageError(message) else { fail("expected UsageError") }
      reports.push((message, code.to_int()))
    })
    |> @hosting.configure(s => { calls.push("configure"); s })
    |> @hosting.service("observer", starting=_ => calls.push("starting"), start=_ => calls.push("start"), started=_ => calls.push("started"),
      stopping=_ => calls.push("stopping"), stop=_ => calls.push("stop"), stopped=_ => calls.push("stopped"))
    |> @hosting.build(_ => calls.push("factory"))
    |> @hosting.run(_ => calls.push("command"))
  assert_eq(result.exit_code().to_int(), 2)
  assert_eq(calls, [])
  assert_eq(parsed, ["invalid"])
  guard result.failures() is [@hosting.UsageError(message)] else { fail("expected one UsageError") }
  assert_true(message.contains("log-format"))
  assert_true(message.contains("log.format"))
  assert_true(message.contains("invalid"))
  assert_eq(reports, [(message, 2)])
}
