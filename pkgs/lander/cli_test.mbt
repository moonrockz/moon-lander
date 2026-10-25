///|
async test "the acme host runs the command between start and stop" {
  let log = []
  let outcome = acme_host(log) |> @hosting.run(_ => log.push("hello"))
  assert_eq(outcome.exit_code(), @hosting.ExitCode::success())
  assert_eq(log, ["greeter started", "hello", "greeter stopped"])
}

///|
async test "cli starting environment is a typed default below the run variable" {
  let production = @conventions.EnvironmentName::parse("Production")
  for (vars, expected) in [({ "ACME_ENVIRONMENT": "Staging" }, "Staging"), ({}, "Production")] {
    let names = []
    let result = @lander.cli(@lander.AppName::parse("acme"), [], env_vars=vars,
      working_dir=@lander_core.AbsolutePath::root(), environment=production)
      |> @hosting.build(b => { names.push(b.environment.environment_name.unwrap().to_string()); () })
      |> @hosting.run(ctx => {
        assert_eq(ctx.environment.environment_name.unwrap().to_string(), expected)
        assert_eq(names, [expected])
      })
    assert_eq(result.exit_code().to_int(), 0)
  }
}
