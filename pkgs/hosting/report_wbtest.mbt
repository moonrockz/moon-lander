///|
test "every pair of exit causes respects precedence for every signal" {
  // signal, config, usage, unhandled failure, stop failure, timeout,
  // application code and clean completion, in precedence order.
  for signal in [SignalKind::Interrupt, Terminate, Quit] {
    let expected = [signal.exit_code(), usage_exit_code(), usage_exit_code(),
      ExitCode::failure(), ExitCode::failure(), ExitCode::failure(),
      ExitCode::from_int(7), ExitCode::success()]
    for first in 0..<expected.length() {
      for second in 0..<expected.length() {
        let failures : Array[Error] = []
        let mut observed_signal = None
        let mut timed_out = false
        let mut application = None
        for cause in [first, second] {
          match cause {
            0 => observed_signal = Some(signal)
            1 => failures.push(@config.FileNotFound(path="config.toml"))
            2 => failures.push(UsageError("bad option"))
            3 => failures.push(HookFailed(0))
            4 => failures.push(HookFailed(1))
            5 => timed_out = true
            6 => application = Some(ExitCode::from_int(7))
            _ => ()
          }
        }
        @expect.expect(select_exit_code(observed_signal, failures, timed_out, application))
          .to_equal(expected[if first < second { first } else { second }])
      }
    }
  }
  @expect.expect(SignalKind::Interrupt.exit_code().to_int()).to_equal(130)
  @expect.expect(SignalKind::Terminate.exit_code().to_int()).to_equal(143)
  @expect.expect(SignalKind::Quit.exit_code().to_int()).to_equal(131)
}

///|
test "configuration and usage failures in every hook and command give 2" {
  let errors : Array[Error] = [@config.FileNotFound(path="config.toml"), UsageError("bad option")]
  for error in errors {
    for target in ["0.Starting", "0.Start", "0.Started", "command", "0.Stopping", "0.Stop", "0.Stopped"] {
      let (_, result) = engine_trace([63], reply=(pending, action) => {
        if action_name(action) == target { pending.failed(error) }
        else { pending.done() }
      })
      @expect.expect(result.exit_code().to_int()).to_equal(2)
      @expect.expect(result.failures().length()).to_equal(1)
    }
  }
}

///|
test "report text uses messages and preserves fallback Show text" {
  let name = @lander_core.AppName::parse("acme")
  let host_error = HostError::InvalidExitCode(code=256)
  let config_error = @config.FileNotFound(path="config.toml")
  @expect.expect(report_text(name, host_error)).to_equal("acme: " + host_error.message())
  @expect.expect(report_text(name, config_error)).to_equal("acme: " + config_error.message())
  @expect.expect(report_text(name, UsageError("bad option"))).to_equal("acme: bad option")
  @expect.expect(UsageError("bad option").message()).to_equal("bad option")
  let error : Error = Failure::Failure("build.invalid_timeout")
  @expect.expect(report_text(name, error)).to_equal("acme: " + error.to_string())
  @expect.expect(report_text(name, error).contains("build.invalid_timeout")).to_be_true()
  try fail("build.invalid_timeout") catch {
    error => @expect.expect(report_text(name, error).contains("build.invalid_timeout")).to_be_true()
  }
}

///|
test "application code is the last set or first request code" {
  for set_after in [false, true] {
    let lifetime = Lifetime::new()
    if !set_after { lifetime.set_exit_code(ExitCode::from_int(3)) }
    lifetime.stop_application(exit_code=ExitCode::from_int(4))
    if set_after { lifetime.set_exit_code(ExitCode::from_int(5)) }
    lifetime.stop_application(exit_code=ExitCode::from_int(9))
    @expect.expect(lifetime.exit_code).to_equal(Some(ExitCode::from_int(if set_after { 5 } else { 4 })))
    @expect.expect(lifetime.requested_code).to_equal(Some(ExitCode::from_int(4)))
  }
  let lifetime = Lifetime::new()
  lifetime.set_exit_code(ExitCode::from_int(3))
  lifetime.stop_application()
  lifetime.stop_application(exit_code=ExitCode::from_int(9))
  @expect.expect(lifetime.exit_code).to_equal(Some(ExitCode::from_int(3)))
}
