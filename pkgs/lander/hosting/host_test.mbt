///|
test "a builder with one service builds a Host[Unit]" {
  let host : @hosting.Host[Unit] = @hosting.builder("acme", ["build"])
    |> @hosting.service("db", start=_ => (), stop=_ => ())
    |> @hosting.build(_ => ())
  ignore(host)
}

///|
test "the factory fixes the services type" {
  let host : @hosting.Host[Array[String]] = @hosting.builder("acme", [])
    |> @hosting.service("log", stop=ctx => ctx.services.push("flushed"))
    |> @hosting.build(_ => [])
  ignore(host)
}

///|
test "exit codes compare by value" {
  @expect.expect(@hosting.ExitCode(1)).to_equal(@hosting.ExitCode(1))
  @expect.expect(@hosting.ExitCode(0) == @hosting.ExitCode(1)).to_equal(false)
}
