///|
fn[S] names(services : Array[HostedService[S]]) -> Array[String] {
  services.map(service => service.name.to_string())
}

///|
test "the host keeps the name, the arguments and the registration order" {
  let host : Host[Unit] = builder(AppName::parse("acme"), ["build", "--verbose"])
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
  let first : HostBuilder[Unit] = builder(AppName::parse("acme"), args)
  let second = first |> service(ServiceName::parse("db"))
  args.push("--late")
  @expect.expect(names(first.services)).to_equal([])
  @expect.expect(names(second.services)).to_equal(["db"])
  @expect.expect(second.args).to_equal(["build"])
}
