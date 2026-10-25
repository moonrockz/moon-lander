///|
fn[S] names(services : Array[HostedService[S]]) -> Array[String] {
  services.map(service => service.name.to_string())
}

///|
test "shutdown timeout defaults to the core 30 second limit and later steps replace it" {
  let first : HostBuilder[Unit] = builder(@lander_core.AppName::parse("timeout"), [])
  let second = first |> shutdown_timeout(@lander_core.TimeLimit::millis(1))
  let third = second |> shutdown_timeout(@lander_core.TimeLimit::seconds(5))
  @expect.expect((first |> build(_ => ())).shutdown_timeout).to_equal(@lander_core.TimeLimit::seconds(30))
  @expect.expect((second |> build(_ => ())).shutdown_timeout).to_equal(@lander_core.TimeLimit::millis(1))
  @expect.expect((third |> build(_ => ())).shutdown_timeout).to_equal(@lander_core.TimeLimit::seconds(5))
  for value in [0, -1] {
    try {
      ignore(@lander_core.TimeLimit::millis(value))
      fail("an invalid limit must not reach the builder")
    } catch {
      @lander_core.InvalidTimeLimit(rule=NotPositive, ..) => ()
      error => raise error
    }
    try {
      ignore(@lander_core.TimeLimit::seconds(value))
      fail("an invalid limit must not reach the builder")
    } catch {
      @lander_core.InvalidTimeLimit(rule=NotPositive, ..) => ()
      error => raise error
    }
  }
}

///|
test "the host keeps the name, the arguments and the registration order" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), ["build", "--verbose"])
    |> service(ServiceName::parse("db"), start=_ => ())
    |> service(ServiceName::parse("cache"), stop=_ => ())
    |> build(_ => ())
  @expect.expect(host.name.to_string()).to_equal("acme")
  @expect.expect(host.args).to_equal(["build", "--verbose"])
  @expect.expect(names(host.services)).to_equal(["db", "cache"])
  @expect.expect(host.services[0].start is Some(_)).to_equal(true)
  @expect.expect(host.services[0].stop is None).to_equal(true)
  @expect.expect(host.services[1].start is None).to_equal(true)
}

///|
test "a step gives a new builder and does not change the earlier one" {
  let args = ["build"]
  let first : HostBuilder[Unit] = builder(@lander_core.AppName::parse("acme"), args)
  let second = first |> service(ServiceName::parse("db"))
  args.push("--late")
  @expect.expect(names(first.services)).to_equal([])
  @expect.expect(names(second.services)).to_equal(["db"])
  @expect.expect(second.args).to_equal(["build"])
}
