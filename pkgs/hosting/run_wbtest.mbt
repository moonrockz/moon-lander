///|
async test "factory failure before start has StartFailed reason" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("test"), [])
    |> build(_ => raise HookFailed(0))
  let result = run(host, _ => fail("command must not run"))
  @expect.expect(result.reason is StartFailed(HookFailed(0))).to_be_true()
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(result.failures().length()).to_equal(1)
}

///|
test "configuration failure before start has StartFailed reason" {
  let result = outcome(HookFailed(1))
  @expect.expect(result.reason is StartFailed(HookFailed(1))).to_be_true()
  @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(result.failures().length()).to_equal(1)
}
