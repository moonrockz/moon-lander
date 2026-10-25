///|
fn application(argv : Array[String]) -> @hosting.HostBuilder[Unit] raise {
  @hosting.builder(@lander_core.AppName::parse("acme"), argv)
  |> @hosting_argparse.command(name => @argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option()],
    flags=[@hosting_argparse.isolated_flag()],
    subcommands=[@argparse.Command("build")]))
}

///|
async test "unknown arguments report the argparse message with code 2 before the factory or any hook" {
  let log = []
  let reports : Array[(String, Int)] = []
  let outcome = application(["--no-such-option"])
    |> @hosting.error_report((error, code) => {
      guard error is @hosting.UsageError(message) else { fail(error.to_string()) }
      reports.push((message, code.to_int()))
    })
    |> @hosting.service("service", starting=_ => log.push("starting"), start=_ => log.push("start"), started=_ => log.push("started"), stopping=_ => log.push("stopping"), stop=_ => log.push("stop"), stopped=_ => log.push("stopped"))
    |> @hosting.build(_ => log.push("factory"))
    |> @hosting.run(_ => log.push("command"))
  @expect.expect(log).to_equal([])
  @expect.expect(outcome.exit_code().to_int()).to_equal(2)
  @expect.expect(outcome.failures().length()).to_equal(1)
  @expect.expect(reports.length()).to_equal(1)
  let expected = @argparse.Command("acme", options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option()], flags=[@hosting_argparse.isolated_flag()], subcommands=[@argparse.Command("build")]).parse(argv=["--no-such-option"]) catch {
    error => error.to_string()
  } noraise { _ => fail("expected argparse error") }
  @expect.expect(reports).to_equal([(expected, 2)])
}

///|
async test "without a command step the bare host accepts no arguments and rejects an extra argument" {
  for argv in [[], ["extra"]] {
    let log = []
    let outcome = @hosting.builder(@lander_core.AppName::parse("bare"), argv)
      |> @hosting.error_report((_, _) => ())
      |> @hosting.service("a", start=_ => log.push("hook"))
      |> @hosting.build(_ => log.push("factory"))
      |> @hosting.run(_ => log.push("command"))
    @expect.expect(outcome.exit_code().to_int()).to_equal(if argv.is_empty() { 0 } else { 2 })
    @expect.expect(log).to_equal(if argv.is_empty() { ["factory", "hook", "command"] } else { [] })
  }
}

///|
async test "the factory hooks and command share one parse result and the command reads its subcommand" {
  let mut calls = 0
  let seen : Array[@argparse.Matches] = []
  let host = @hosting.builder(@lander_core.AppName::parse("acme"), ["build"])
    |> @hosting_argparse.command(name => {
      calls += 1
      @expect.expect(name).to_equal("acme") catch { _ => abort("wrong application name") }
      @argparse.Command(name, subcommands=[@argparse.Command("build")])
    })
    |> @hosting.service("a", start=ctx => seen.push(ctx.args), stop=ctx => seen.push(ctx.args))
    |> @hosting.build(ctx => seen.push(ctx.args))
  for _ in 0..<2 {
    let outcome = host |> @hosting.run(ctx => {
      seen.push(ctx.args)
      @expect.expect(ctx.args.subcommand is Some(("build", _))).to_be_true()
    })
    @expect.expect(outcome.exit_code().to_int()).to_equal(0)
  }
  @expect.expect(calls).to_equal(2)
  @expect.expect(seen.length()).to_equal(8)
  for offset in [0, 4] {
    for i in 1..<4 { @expect.expect(physical_equal(seen[offset], seen[offset + i])).to_be_true() }
  }
  @expect.expect(physical_equal(seen[0], seen[4])).to_be_false()
}

///|
async test "standard flags reach discovery and never become configuration keys" {
  let expected = @conventions.DiscoveryOptions::new(environment="Staging", config=Explicit("../configs/project.yaml"), isolated=true, project="packages/core")
  let outcome = application(["build", "--environment", "Staging", "--config", "../configs/project.yaml", "--isolated", "--project", "packages/core"])
    |> @hosting.build(ctx => {
      @expect.expect(ctx.discovery_options).to_equal(expected)
      @expect.expect(ctx.args.subcommand is Some(("build", _))).to_be_true()
      for key in ["environment", "config", "isolated", "project"] {
        @expect.expect(ctx.config.get(@config.KeyPath::parse(key)) is None).to_be_true()
      }
    })
    |> @hosting.run(ctx => {
      @expect.expect(ctx.args.values.get("environment")).to_equal(Some(["Staging"]))
      for key in ["environment", "config", "isolated", "project"] {
        @expect.expect(ctx.config.get(@config.KeyPath::parse(key)) is None).to_be_true()
      }
    })
  @expect.expect(outcome.exit_code().to_int()).to_equal(0)
}

///|
async test "empty standard option values give code 2 and run no factory or hook" {
  for flag in ["--environment", "--config", "--project"] {
    for argv in [[flag + "="], [flag, ""], ["build", flag + "="]] {
      let log = []
      let outcome = application(argv)
        |> @hosting.error_report((error, code) => {
          @expect.expect(error is @hosting.UsageError(_)).to_be_true()
          @expect.expect(code.to_int()).to_equal(2)
        })
        |> @hosting.service("a", start=_ => log.push("hook"), stop=_ => log.push("stop"))
        |> @hosting.build(_ => log.push("factory"))
        |> @hosting.run(_ => log.push("command"))
      @expect.expect(log).to_equal([])
      @expect.expect(outcome.exit_code().to_int()).to_equal(2)
      @expect.expect(outcome.failures()[0] is @hosting.UsageError(_)).to_be_true()
    }
  }
}
