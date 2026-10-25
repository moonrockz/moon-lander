///|
fn environment_of(host : Host[Unit]) -> HostEnvironment raise {
  let settings = resolve_settings(host)
  let parsed = parse_arguments(host, env=settings.variables)
  resolve_environment(host, settings, parsed.discovery_options)
}

///|
fn environment_builder(args? : Array[String] = [], vars? : Map[String, String] = {}) -> HostBuilder[Unit] raise {
  builder(@lander_core.AppName::parse("acme"), args, env_vars=vars,
    working_dir=@lander_core.AbsolutePath::parse("/work/repo"))
  |> command(name => @argparse.Command(name, options=[@hosting_argparse.environment_option()]))
}

///|
test "no environment name makes every named check false" {
  let environment = environment_of(environment_builder() |> build(_ => ()))
  assert_eq(environment.application_name.to_string(), "acme")
  assert_eq(environment.environment_name, None)
  assert_true(!environment.is_environment(@conventions.EnvironmentName::parse("custom")))
  assert_true(!environment.is_development())
  assert_true(!environment.is_staging())
  assert_true(!environment.is_production())
}

///|
test "environment checks ignore case and preserve the name for exact file matches" {
  for (text, expected) in [("dEvElOpMeNt", (true, false, false)), ("sTaGiNg", (false, true, false)), ("pRoDuCtIoN", (false, false, true))] {
    let environment = environment_of(environment_builder(vars={ "ACME_ENVIRONMENT": text }) |> build(_ => ()))
    assert_eq(environment.environment_name.unwrap().to_string(), text)
    assert_eq((environment.is_development(), environment.is_staging(), environment.is_production()), expected)
    assert_true(environment.is_environment(@conventions.EnvironmentName::parse(text.to_upper())))
    assert_true(!environment.is_environment(@conventions.EnvironmentName::parse("custom")))
  }
  let custom = environment_of(environment_builder(vars={ "ACME_ENVIRONMENT": "DÉVELOPPEMENT" }) |> build(_ => ()))
  assert_true(custom.is_environment(@conventions.EnvironmentName::parse("développement")))
}

///|
test "flag then run variable then starting default resolve before discovery" {
  let production = @conventions.EnvironmentName::parse("Production")
  for (args, vars, expected) in [
    (["--environment", "Staging"], { "ACME_ENVIRONMENT": "Production" }, "Staging"),
    ([], { "ACME_ENVIRONMENT": "Staging" }, "Staging"),
    ([], {}, "Production"),
    ([], { "ACME_ENVIRONMENT": "" }, "Production"),
    (["--environment", "Staging"], { "ACME_ENVIRONMENT": "../invalid" }, "Staging"),
  ] {
    let host = builder(@lander_core.AppName::parse("acme"), args, env_vars=vars,
      working_dir=@lander_core.AbsolutePath::root(), environment=production)
      |> command(name => @argparse.Command(name, options=[@hosting_argparse.environment_option()])) |> build(_ => ())
    let settings = resolve_settings(host)
    let parsed = parse_arguments(host, env=settings.variables)
    let environment = resolve_environment(host, settings, parsed.discovery_options)
    assert_eq(environment.environment_name.map(name => name.to_string()), Some(expected))
    assert_eq(environment_options(parsed.discovery_options, environment).environment, Some(expected))
  }
}

///|
test "bootstrap uses the final prefix and supplied snapshot even with the variable source off" {
  let vars = { "ACME_ENVIRONMENT": "Production", "TOOL_ENVIRONMENT": "Staging" }
  let builder = environment_builder(vars~) |> skip_env_source()
    |> env_prefix(@lander_core.EnvPrefix::parse("TOOL"))
  vars["TOOL_ENVIRONMENT"] = "../changed"
  let host = builder |> build(_ => ())
  let settings = resolve_settings(host, read_variables=() => abort("must not read process"))
  let parsed = parse_arguments(host, env=settings.variables)
  assert_true(resolve_environment(host, settings, parsed.discovery_options).is_staging())
  let replaced = builder |> env_vars({ "TOOL_ENVIRONMENT": "Development" }) |> build(_ => ())
  assert_true(environment_of(replaced).is_development())
}

///|
test "empty variable is unset without a default and invalid variables fail even with environments off" {
  assert_eq(environment_of(environment_builder(vars={ "ACME_ENVIRONMENT": "" }) |> build(_ => ())).environment_name, None)
  for text in ["../x", "user", "local", "a\\b", "a\nb"] {
    let host = environment_builder(vars={ "ACME_ENVIRONMENT": text }) |> build(_ => ())
    try { ignore(environment_of(host)) } catch {
      @config.InvalidEnvironmentName(name~, ..) as error => {
        assert_eq(name, text)
        assert_eq(select_exit_code(None, [error], false, None).to_int(), 2)
      }
      error => raise error
    } noraise { _ => fail("expected InvalidEnvironmentName") }
  }
}

///|
test "default environment enables the conventions environment part and the resolved name reaches it" {
  let first = environment_builder() |> app_dirs()
  let second = first |> default_environment(@conventions.EnvironmentName::parse("Production"))
  let third = second |> default_environment(@conventions.EnvironmentName::parse("Staging"))
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/work/repo", [{ name: "acme.toml", kind: File }])
    .with_file("/work/repo/acme.toml", "")
  assert_true(!settings_config(first |> build(_ => ()), tree~).reports().iter().any(r => r.kind is File(EnvironmentFile)))
  for (builder, expected) in [(second, "Production"), (third, "Staging")] {
    let config = settings_config(builder |> build(_ => ()), tree~)
    assert_true(config.reports().iter().any(r => r.kind is File(EnvironmentFile) && r.candidates.contains("/work/repo/acme.\{expected}.toml")))
  }
  let flag = environment_builder(args=["--environment", "Staging"], vars={ "ACME_ENVIRONMENT": "Development" })
    |> app_dirs() |> default_environment(@conventions.EnvironmentName::parse("Production"))
  assert_true(settings_config(flag |> build(_ => ()), tree~).reports().iter().any(r => r.kind is File(EnvironmentFile) && r.candidates.contains("/work/repo/acme.Staging.toml")))
}

///|
test "content root defaults to working directory and later typed steps replace it immutably" {
  let first = environment_builder()
  let second = first |> content_root(@lander_core.AbsolutePath::parse("/content"))
    |> working_dir(@lander_core.AbsolutePath::parse("/elsewhere"))
  let third = second |> content_root(@lander_core.AbsolutePath::parse("C:\\work\\repo"))
  assert_eq(environment_of(first |> build(_ => ())).content_root.to_string(), "/work/repo")
  assert_eq(environment_of(second |> build(_ => ())).content_root.to_string(), "/content")
  assert_eq(environment_of(third |> build(_ => ())).content_root.to_string(), "C:/work/repo")
  let windows = first |> working_dir(@lander_core.AbsolutePath::parse("C:\\work\\repo"))
  assert_eq(environment_of(windows |> build(_ => ())).content_root.to_string(), "C:/work/repo")
}
