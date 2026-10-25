///|
fn settings_host(vars : &IntoEnvVars, name? : String = "acme") -> Host[Unit] raise {
  builder(@lander_core.AppName::parse(name), [], env_vars=vars,
    working_dir=@lander_core.AbsolutePath::parse("/w")) |> build(_ => ())
}

///|
fn settings_config(host : Host[Unit], tree? : @config.FileTree = @config.FileTree::new(complete=true)) -> @config.Config raise {
  let settings = resolve_settings(host)
  let parsed = parse_arguments(host, env=settings.variables)
  let builder = configuration_builder(host, settings, parsed.discovery_options)
    |> @config.platform(Linux) |> @config.format(@toml.format())
  guard @config.load(builder, tree) is Done(config) else { fail("expected a complete configuration") }
  config
}

///|
test "default prefix and override load log.format" {
  let vars = { "MY_TOOL_LOG__FORMAT": "json", "MT_LOG__FORMAT": "text" }
  let first = builder(@lander_core.AppName::parse("my-tool"), [], env_vars=vars)
  assert_eq(@config.get_text(settings_config(first |> build(_ => ())), "log.format"), "json")
  let second = first |> env_prefix(@lander_core.EnvPrefix::parse("MT"))
  assert_eq(@config.get_text(settings_config(second |> build(_ => ())), "log.format"), "text")
}

///|
test "reserved names stay out and variable source reports priority 600" {
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars={
    "ACME_ENVIRONMENT": "Staging", "ACME_HOME": "/tmp/acme",
    "ACME_LOG_DIR": "/logs", "ACME_OTHER": "yes", "ACME_TOKEN": "secret",
  }) |> reserve_env(["ACME_LOG_DIR"]) |> reserve_env(["ACME_TOKEN"]) |> build(_ => ())
  let config = settings_config(host)
  assert_eq(config.value(), @config.ConfigValue::from_json({ "other": "yes" }))
  let report = config.reports().iter().find_first(r => r.kind is Environment).unwrap()
  assert_eq(report.priority, 600)
  assert_true(report.status is Loaded)
}

///|
test "variables beat a file through the host source and conventions composition" {
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars={ "ACME_LOG__FORMAT": "json" },
    working_dir=@lander_core.AbsolutePath::parse("/w")) |> app_dirs() |> build(_ => ())
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/w", [{ name: "acme.toml", kind: File }])
    .with_file("/w/acme.toml", "log.format = \"text\"")
  let config = settings_config(host, tree~)
  assert_eq(@config.get_text(config, "log.format"), "json")
  assert_true(config.reports().iter().any(r => r.path == Some("/w/acme.toml") && r.status is Loaded))
  assert_true(config.reports().iter().any(r => r.kind is Environment && r.priority == 600))
}

///|
test "later variable and directory steps replace starting values without process reads" {
  let first = builder(@lander_core.AppName::parse("acme"), [], env_vars={ "ACME_A": "1" },
    working_dir=@lander_core.AbsolutePath::parse("/a"))
  let second = first |> env_vars({ "ACME_B": "2" }) |> working_dir(@lander_core.AbsolutePath::parse("/b"))
  let host = second |> build(_ => ())
  let settings = resolve_settings(host, read_variables=() => abort("no process variables"),
    read_directory=() => abort("no process directory"))
  assert_eq(settings.variables, { "ACME_B": "2" })
  assert_eq(settings.directory.to_string(), "/b")
  let core = configuration_builder(host, settings, @conventions.DiscoveryOptions::new())
  assert_eq(core.given_env_vars(), Some(settings.variables))
  assert_eq(core.given_working_dir(), Some("/b"))
  assert_eq(settings_config(host).value(), @config.ConfigValue::from_json({ "b": 2 }))
  assert_eq(settings_config(first |> build(_ => ())).value(), @config.ConfigValue::from_json({ "a": 1 }))
  let discovered = settings_config(second |> app_dirs() |> build(_ => ()))
  assert_true(discovered.reports().iter().any(r => r.candidates.contains("/b/acme.toml")))
}

///|
test "each omitted setting is filled exactly once and explicit settings never read process inputs" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), []) |> build(_ => ())
  let mut variable_reads = 0
  let mut directory_reads = 0
  let read_variables = () => { variable_reads += 1; { "ACME_A": "1" } }
  let read_directory = () => { directory_reads += 1; @lander_core.AbsolutePath::root() }
  let settings = resolve_settings(host, read_variables~, read_directory~)
  assert_eq((variable_reads, directory_reads), (1, 1))
  assert_eq(settings.variables, { "ACME_A": "1" })
  assert_eq(settings.directory.to_string(), "/")
  ignore(resolve_settings(builder(host.name, [], env_vars=(Map([]) : Map[String, String])) |> build(_ => ()), read_variables~, read_directory~))
  assert_eq((variable_reads, directory_reads), (1, 2))
  ignore(resolve_settings(builder(host.name, [], working_dir=@lander_core.AbsolutePath::root()) |> build(_ => ()), read_variables~, read_directory~))
  assert_eq((variable_reads, directory_reads), (2, 2))
  ignore(resolve_settings(settings_host((Map([]) : Map[String, String])), read_variables=() => abort("no variable read"), read_directory=() => abort("no directory read")))
}

///|
test "map literal and parsed JSON fixture give the same snapshot and report" {
  let from_map = settings_host({ "ACME_LOG__FORMAT": "json" })
  let from_json = settings_host(@json.parse("{\"ACME_LOG__FORMAT\":\"json\"}"))
  assert_eq(resolve_settings(from_map).variables, resolve_settings(from_json).variables)
  assert_eq(settings_config(from_map).value(), settings_config(from_json).value())
  assert_eq(settings_config(from_map).reports(), settings_config(from_json).reports())
}

///|
test "JSON strings numbers booleans arrays objects null and keys follow D14" {
  let vars : Json = {
    "ACME_PORT": 8080, "ACME_DEBUG": true, "ACME_TAGS": ["a", "b"],
    "ACME_OBJECT": { "nested": 1 }, "ACME_TEXT": "001", "ACME_NULL": null,
    "Mixed_Key": "kept", "lower": false, "fraction": 1.5,
  }
  let host = settings_host(vars)
  let snapshot = resolve_settings(host).variables
  assert_eq(snapshot, {
    "ACME_PORT": "8080", "ACME_DEBUG": "true", "ACME_TAGS": "[\"a\",\"b\"]",
    "ACME_OBJECT": "{\"nested\":1}", "ACME_TEXT": "001", "Mixed_Key": "kept",
    "lower": "false", "fraction": "1.5",
  })
  let config = settings_config(host)
  assert_eq(config.value(), @config.ConfigValue::from_json({
    "port": 8080, "debug": true, "tags": ["a", "b"], "object": { "nested": 1 }, "text": 1,
  }))
}

///|
test "every non-object JSON root gives usage code 2 before a directory read" {
  for vars in ([null, true, 1, "text", ["ACME_PORT"]] : Array[Json]) {
    try {
      ignore(resolve_settings(settings_host(vars), read_directory=() => abort("conversion must fail first")))
    } catch {
      UsageError(message) as error => {
        assert_true(message.contains("JSON object"))
        assert_eq(select_exit_code(None, [error], false, None).to_int(), 2)
      }
      error => raise error
    } noraise { _ => fail("expected UsageError") }
  }
}

///|
test "one final prefix reaches app home and source even when set after app_dirs" {
  let host = builder(@lander_core.AppName::parse("my-tool"), [], env_vars={
    "MT_HOME": "/custom", "MT_LOG__FORMAT": "json", "MY_TOOL_HOME": "/wrong",
  }, working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> app_dirs() |> env_prefix(@lander_core.EnvPrefix::parse("MT")) |> build(_ => ())
  let config = settings_config(host)
  assert_eq(@config.get_text(config, "log.format"), "json")
  assert_true(config.reports().iter().any(r => r.candidates.contains("/custom/my-tool.toml")))
  assert_true(!config.reports().iter().any(r => r.candidates.contains("/wrong/my-tool.toml")))
}

///|
test "skipped source reports skipped while conventions and argparse retain the set" {
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars={
    "ACME_HOME": "/custom", "ACME_ENVIRONMENT": "Staging", "ACME_A": "1",
  }, working_dir=@lander_core.AbsolutePath::root()) |> app_dirs() |> skip_env_source() |> build(_ => ())
  let config = settings_config(host)
  assert_true(config.get(@config.KeyPath::parse("a")) is None)
  assert_true(config.reports().iter().any(r => r.kind is Environment && r.status is Skipped && r.priority == 600))
  assert_true(config.reports().iter().any(r => r.candidates.contains("/custom/acme.toml")))
  let vars = resolve_settings(host).variables
  assert_eq(@conventions.environment_name(@conventions.base("acme") |> @conventions.environments(), vars), Some("Staging"))
  let command_host = builder(host.name, [], env_vars=vars) |> skip_env_source()
    |> command(name => @argparse.Command(name, options=[@argparse.OptionArg("a", env="ACME_A")])) |> build(_ => ())
  let parsed = parse_arguments(command_host, env=resolve_settings(command_host).variables)
  assert_eq(parsed.matches.values.get("a"), Some(["1"]))
}

///|
test "starting environment remains a default for conventions" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), [], environment="Staging") |> build(_ => ())
  assert_eq(host.environment, Some("Staging"))
  let conventions = @conventions.base("acme") |> @conventions.environments(default=host.environment.unwrap())
  assert_eq(@conventions.environment_name(conventions, Map([])), Some("Staging"))
  assert_eq(@conventions.environment_name(conventions, { "ACME_ENVIRONMENT": "Production" }), Some("Production"))
}

///|
test "explicit settings compose equal configuration and reports on every target" {
  let first = builder(@lander_core.AppName::parse("acme"), [], env_vars={
    "ACME_LOG__FORMAT": "json", "HOME": "/home/test",
  }, working_dir=@lander_core.AbsolutePath::parse("/w")) |> app_dirs() |> build(_ => ())
  let second = builder(first.name, [], env_vars=({
    "ACME_LOG__FORMAT": "json", "HOME": "/home/test",
  } : Json), working_dir=@lander_core.AbsolutePath::parse("/w")) |> app_dirs() |> build(_ => ())
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/w", [{ name: "acme.toml", kind: File }])
    .with_file("/w/acme.toml", "log.format = \"text\"\nfile_only = true")
  let config = settings_config(first, tree~)
  let equivalent = settings_config(second, tree~)
  assert_eq(config.value(), @config.ConfigValue::from_json({ "log": { "format": "json" }, "file_only": true }))
  assert_eq(config.value(), equivalent.value())
  assert_eq(config.reports(), equivalent.reports())
}

///|
test "every composed reader sees one set including environment and HOME" {
  let variables = { "ACME_ENVIRONMENT": "Staging", "ACME_LOG__FORMAT": "json", "HOME": "/home/test" }
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=variables,
    working_dir=@lander_core.AbsolutePath::parse("/w")) |> app_dirs() |> build(_ => ())
  let settings = resolve_settings(host, read_variables=() => abort("explicit set must win"))
  assert_eq(settings.variables, variables)
  assert_eq(@conventions.environment_name(@conventions.base("acme") |> @conventions.environments(), settings.variables), Some("Staging"))
  let config = settings_config(host)
  assert_eq(@config.get_text(config, "log.format"), "json")
  assert_true(config.reports().iter().any(r => r.candidates.contains("/home/test/.acme/acme.toml")))
}
