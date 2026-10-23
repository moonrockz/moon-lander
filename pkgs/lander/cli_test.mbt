///|
async test "the acme host runs the command between start and stop" {
  let log = []
  let outcome = acme_host(log) |> @hosting.run(_ => log.push("hello"))
  assert_eq(outcome.exit_code, @hosting.ExitCode(0))
  assert_eq(log, ["greeter started", "hello", "greeter stopped"])
}
