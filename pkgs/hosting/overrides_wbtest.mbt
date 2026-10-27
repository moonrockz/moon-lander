///|
fn mapping(id : String, key : String, action? : MappingAction = Set, parse? : (String) -> @config.ConfigValue raise) -> Mapping raise {
  map(OverrideOption::parse(id), @config.KeyPath::parse(key), action~, parse?)
}

///|
fn mapped_config(command : @argparse.Command, argv : Array[String], mappings : Array[Mapping], env? : Map[String, String] = {}) -> @config.Config raise {
  let matches = command.parse(argv=argv[:], env~)
  @config.build([to_overrides(matches, mappings)])
}

///|
test "override ids parse once and reject empty and every discovery id" {
  for id in ["", "environment", "config", "isolated", "project"] {
    try { ignore(OverrideOption::parse(id)); fail("expected invalid mapping id") } catch {
      InvalidOverrideOption(input~, reason~) => {
        assert_eq(input, id)
        assert_true(!reason.is_empty())
      }
      error => raise error
    }
  }
  for id in ["x", "log-format", "verbose", "Project"] {
    assert_eq(OverrideOption::parse(id).to_string(), id)
  }
}

///|
test "mapped flags counts set and append preserve their types and exclude unmapped and defaults" {
  let command = @argparse.Command("acme",
    flags=[@argparse.FlagArg("flag", negatable=true), @argparse.FlagArg("verbose", short='v', action=Count), @argparse.FlagArg("dry-run")],
    options=[@argparse.OptionArg("single"), @argparse.OptionArg("items", action=Append), @argparse.OptionArg("fallback", default_values=["text"])])
  let mappings = [mapping("flag", "enabled", action=Flag), mapping("verbose", "log.verbosity", action=Count), mapping("single", "single"), mapping("items", "items", action=Append), mapping("fallback", "fallback")]
  let config = mapped_config(command, ["--flag", "-vvv", "--single", "text", "--items", "one", "--items", "two", "--dry-run"], mappings)
  assert_eq(config.value(), @config.ConfigValue::from_json({ "enabled": true, "log": { "verbosity": 3 }, "single": "text", "items": ["one", "two"] }))
  let one = mapped_config(command, ["--no-flag", "--items", "one"], mappings)
  assert_eq(one.value(), @config.ConfigValue::from_json({ "enabled": false, "items": ["one"] }))
  assert_eq(mapped_config(command, [], mappings).value(), @config.fields([]))
}

///|
test "Env values count as explicit with the same flag count set and append types" {
  let command = @argparse.Command("acme",
    flags=[@argparse.FlagArg("enabled", env="ENABLED"), @argparse.FlagArg("verbose", action=Count, env="VERBOSE")],
    options=[@argparse.OptionArg("single", env="SINGLE"), @argparse.OptionArg("items", action=Append, env="ITEMS")])
  let config = mapped_config(command, [], [mapping("enabled", "enabled", action=Flag), mapping("verbose", "verbosity", action=Count), mapping("single", "single"), mapping("items", "items", action=Append)],
    env={ "ENABLED": "false", "VERBOSE": "2", "SINGLE": "yaml", "ITEMS": "one" })
  assert_eq(config.value(), @config.ConfigValue::from_json({ "enabled": false, "verbosity": 2, "single": "yaml", "items": ["one"] }))
}

///|
test "an explicit zero Env count remains integer zero and custom parsers receive zero text" {
  let command = @argparse.Command("acme", flags=[@argparse.FlagArg("enabled", env="ENABLED"), @argparse.FlagArg("verbose", action=Count, env="VERBOSE")])
  let env = { "ENABLED": "false", "VERBOSE": "0" }
  let config = mapped_config(command, [], [mapping("enabled", "enabled", action=Flag), mapping("verbose", "verbosity", action=Count)], env~)
  assert_eq(config.value(), @config.ConfigValue::from_json({ "enabled": false, "verbosity": 0 }))
  let seen = []
  let parse : (String) -> @config.ConfigValue raise = text => { seen.push(text); @config.int(@string.parse_int64(text)) }
  let custom = mapped_config(command, [], [mapping("verbose", "verbosity", action=Count, parse~)], env~)
  assert_eq(custom.value(), @config.ConfigValue::from_json({ "verbosity": 0 }))
  assert_eq(seen, ["0"])
  try {
    ignore(mapped_config(command, [], [mapping("verbose", "verbosity", action=Count, parse=_ => raise UsageError("positive count required"))], env~))
    fail("expected UsageError")
  } catch {
    UsageError(message) => assert_true(message.contains("with value 0"))
    error => raise error
  }
}

///|
test "custom parsers convert each append text and scalar text with typed configuration values" {
  let command = @argparse.Command("acme", options=[@argparse.OptionArg("port"), @argparse.OptionArg("sizes", action=Append)])
  let parse : (String) -> @config.ConfigValue raise = text => @config.int(@string.parse_int64(text))
  let config = mapped_config(command, ["--port", "8080", "--sizes", "1", "--sizes", "2"], [mapping("port", "server.port", parse~), mapping("sizes", "sizes", action=Append, parse~)])
  assert_eq(config.value(), @config.ConfigValue::from_json({ "server": { "port": 8080 }, "sizes": [1, 2] }))
  let one = mapped_config(command, ["--sizes", "42"], [mapping("sizes", "sizes", action=Append, parse~)])
  assert_eq(one.value(), @config.ConfigValue::from_json({ "sizes": [42] }))
}

///|
test "global arguments and only the selected nested subcommand map without duplicate global parsing" {
  let calls = Ref(0)
  let parse : (String) -> @config.ConfigValue raise = text => { calls.val += 1; @config.string(text) }
  let command = @argparse.Command("acme", options=[@argparse.OptionArg("format", global=true)],
    subcommands=[@argparse.Command("build", subcommands=[@argparse.Command("release", options=[@argparse.OptionArg("output")])]), @argparse.Command("unused", options=[@argparse.OptionArg("output", default_values=["unused"])])])
  for argv in [["--format", "json", "build", "release", "--output", "dist"], ["build", "release", "--format", "json", "--output", "dist"]] {
    let config = mapped_config(command, argv, [mapping("format", "log.format", parse~), mapping("output", "output")])
    assert_eq(config.value(), @config.ConfigValue::from_json({ "log": { "format": "json" }, "output": "dist" }))
  }
  assert_eq(calls.val, 2)
}

///|
test "deeper explicit values win while subcommand defaults keep the explicit ancestor" {
  let command = @argparse.Command("acme", options=[@argparse.OptionArg("format")],
    subcommands=[@argparse.Command("build", options=[@argparse.OptionArg("format", default_values=["text"])])])
  let mappings = [mapping("format", "log.format")]
  assert_eq(@config.get_text(mapped_config(command, ["--format", "yaml", "build"], mappings), "log.format"), "yaml")
  assert_eq(@config.get_text(mapped_config(command, ["--format", "yaml", "build", "--format", "json"], mappings), "log.format"), "json")
}

///|
test "a command snapshots mappings and a later command replaces them" {
  let mappings = [mapping("format", "log.format")]
  let first : HostBuilder[String] = builder(@lander_core.AppName::parse("acme"), ["--format", "json"], env_vars=({} : Map[String, String]), working_dir=@lander_core.AbsolutePath::root())
  let second = first |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("format")]), mappings~)
  mappings.clear()
  assert_eq(first.mappings.length(), 0)
  assert_eq(second.mappings.length(), 1)
  let third = second |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("format")]))
  assert_eq(third.mappings.length(), 0)
  let config = second |> build(b => @config.get_text(b.config, "log.format")) |> injected_run
  assert_eq(config.context.services, "json")
}

///|
test "a parser default leaves the real file value intact on every target" {
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=({} : Map[String, String]), working_dir=@lander_core.AbsolutePath::root())
    |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("format", default_values=["text"])]), mappings=[mapping("format", "log.format")])
    |> configure(s => s |> @config.format(@toml.format()) |> @config.file("/acme.toml"))
    |> files(@config.FileTree::new(complete=true).with_file("/acme.toml", "log.format = \"json\""))
    |> build(b => @config.get_text(b.config, "log.format"))
  let loaded = injected_run(host)
  assert_eq(loaded.context.services, "json")
  assert_true(loaded.context.config.origins(@config.KeyPath::parse("log.format"))[0].kind is File(_))
}

///|
test "real host override source is last and the factory sees the result on all targets" {
  let tree = @config.FileTree::new(complete=true).with_listing("/w", [{ name: "acme.toml", kind: File }])
    .with_file("/w/acme.toml", "log.format = \"text\"")
  let host = builder(@lander_core.AppName::parse("acme"), ["--log-format", "json"],
      env_vars={ "ACME_LOG__FORMAT": "yaml" }, working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("log-format")]), mappings=[mapping("log-format", "log.format")])
    |> configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format()))
    |> app_dirs() |> files(tree) |> build(b => @config.get_text(b.config, "log.format"))
  let loaded = injected_run(host)
  assert_eq(loaded.context.services, "json")
  let config = loaded.context.config
  assert_true(config.origins(@config.KeyPath::parse("log.format"))[0].kind is Overrides)
  let reports = config.reports()
  assert_true(reports[reports.length() - 1].kind is Overrides)
  assert_eq(reports[reports.length() - 1].priority, 700)
  assert_eq(reports[reports.length() - 2].priority, 600)
}

///|
test "host converts parsing failures to usage before any configuration callback" {
  let calls = Ref(0)
  let mappings = [mapping("port", "port", parse=_ => raise UsageError("port must be an integer"))]
  let host = builder(@lander_core.AppName::parse("acme"), ["--port", "bad"], env_vars=({} : Map[String, String]), working_dir=@lander_core.AbsolutePath::root())
    |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("port")]), mappings~)
    |> configure(s => { calls.val += 1; s }) |> build(_ => { calls.val += 1 })
  try { ignore(injected_run(host)); fail("expected usage error") } catch {
    UsageError(message) as error => {
      assert_true(message.contains("port must be an integer"))
      assert_eq(outcome(error).exit_code().to_int(), 2)
    }
    error => raise error
  }
  assert_eq(calls.val, 0)
}
