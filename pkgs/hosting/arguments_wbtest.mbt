///|
fn[S] parse_test_arguments(host : Host[S]) -> ParsedArguments raise UsageError {
  parse_arguments(host, env=resolve_settings(host).variables)
}

///|
fn argument_host(argv : Array[String]) -> Host[Unit] raise {
  builder(@lander_core.AppName::parse("acme"), argv)
  |> @hosting_argparse.command(name => @argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option()],
    flags=[@hosting_argparse.isolated_flag()],
    subcommands=[@argparse.Command("build", subcommands=[@argparse.Command("release")])]))
  |> build(_ => ())
}

///|
test "the adapter keeps argparse error text and usage code" {
  let argv = ["--no-such-option"]
  let expected = @argparse.Command("acme").parse(argv=argv[:]) catch {
    error => error.to_string()
  } noraise { _ => fail("expected an argparse error") }
  try parse_test_arguments(builder(@lander_core.AppName::parse("acme"), argv) |> build(_ => ())) catch {
    UsageError(message) as error => {
      @expect.expect(message).to_equal(expected)
      @expect.expect(select_exit_code(None, [error], false, None)).to_equal(usage_exit_code())
    }
    error => fail(error.to_string())
  } noraise { _ => fail("expected UsageError") }
}

///|
test "an empty command uses the application name and rejects extra arguments" {
  let name = @lander_core.AppName::parse("bare")
  let host = builder(name, []) |> build(_ => ())
  @expect.expect(parse_test_arguments(host).matches.subcommand is None).to_be_true()
  try parse_test_arguments(builder(name, ["extra"]) |> build(_ => ())) catch {
    UsageError(message) => @expect.expect(message.contains("Usage: bare")).to_be_true()
  } noraise { _ => fail("expected UsageError") }
}

///|
test "absent standard flags leave discovery at its defaults" {
  @expect.expect(parse_test_arguments(argument_host([])).discovery_options).to_equal(@conventions.DiscoveryOptions::new())
}

///|
test "each standard flag fills only its discovery field" {
  let cases : Array[(Array[String], @conventions.DiscoveryOptions)] = [
    (["--environment", "Staging"], @conventions.DiscoveryOptions::new(environment="Staging")),
    (["--config", "../configs/project.yaml"], @conventions.DiscoveryOptions::new(config=Explicit("../configs/project.yaml"))),
    (["--isolated"], @conventions.DiscoveryOptions::new(isolated=true)),
    (["--project", "core"], @conventions.DiscoveryOptions::new(project="core")),
    (["--project", "packages/core"], @conventions.DiscoveryOptions::new(project="packages/core")),
  ]
  for (argv, expected) in cases {
    @expect.expect(parse_test_arguments(argument_host(argv)).discovery_options).to_equal(expected)
  }
}

///|
test "all standard flags are global through nested subcommands" {
  let parsed = parse_test_arguments(argument_host(["build", "release", "--environment", "Staging", "--config", "app.toml", "--isolated", "--project", "core"]))
  @expect.expect(parsed.discovery_options).to_equal(@conventions.DiscoveryOptions::new(environment="Staging", config=Explicit("app.toml"), isolated=true, project="core"))
  @expect.expect(parsed.matches.subcommand is Some(("build", _))).to_be_true()
}

///|
test "each empty or missing standard value is a usage error" {
  for flag in ["--environment", "--config", "--project"] {
    for argv in [[flag + "="], [flag, ""], [flag]] {
      try parse_test_arguments(argument_host(argv)) catch {
        UsageError(message) as error => {
          @expect.expect(message.contains(flag)).to_be_true()
          @expect.expect(select_exit_code(None, [error], false, None)).to_equal(usage_exit_code())
        }
        error => fail(error.to_string())
      } noraise { _ => fail("expected UsageError for \{flag}") }
    }
  }
}

///|
test "the command step preserves the earlier builder and the last command wins" {
  let first : HostBuilder[Unit] = builder(@lander_core.AppName::parse("acme"), [])
  let second = first |> command(name => @argparse.Command(name, subcommand_required=true))
  let third = second |> command(name => @argparse.Command(name))
  @expect.expect(first.make_command is None).to_be_true()
  @expect.expect(second.make_command is Some(_)).to_be_true()
  @expect.expect(parse_test_arguments(third |> build(_ => ())).matches.subcommand is None).to_be_true()
}
