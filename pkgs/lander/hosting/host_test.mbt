///|
test "a builder with one service builds a Host[Unit]" {
  let host : @hosting.Host[Unit] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      ["build"],
    )
    |> @hosting.service(
      @hosting.ServiceName::parse("db"),
      start=_ => (),
      stop=_ => (),
    )
    |> @hosting.build(_ => ())
  ignore(host)
}

///|
test "the factory fixes the services type" {
  let host : @hosting.Host[Array[String]] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      [],
    )
    |> @hosting.service(
      @hosting.ServiceName::parse("log"),
      stop=ctx => ctx.services.push("flushed"),
    )
    |> @hosting.build(_ => [])
  ignore(host)
}

///|
test "a second service with the same name is a fault" {
  let db = @hosting.ServiceName::parse("db")
  let builder : @hosting.HostBuilder[Unit] = @hosting.builder(
      @hosting.AppName::parse("acme"),
      [],
    )
    |> @hosting.service(db)
  let result : Result[@hosting.HostBuilder[Unit], @hosting.HostError] = try
    Ok(builder |> @hosting.service(db))
  catch {
    err => Err(err)
  }
  guard result is Err(@hosting.DuplicateService(name~)) else {
    fail("expected DuplicateService")
  }
  @expect.expect(name).to_equal(db)
}
