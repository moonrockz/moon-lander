///|
async fn main {
  let kind : @hosting.SignalKind = match @env.get_env_var("LANDER_COMPLETION_SIGNAL") {
    Some("interrupt") => Interrupt
    Some("terminate") => Terminate
    _ => fail("missing completion fixture signal")
  }
  let captured : Ref[@runtime.Session?] = Ref(None)
  let hooks = Ref(0)
  @bridge.run_with_session(@sinks.SessionSettings::standard(), session => {
    captured.val = Some(session)
    (session.logger() : &@logging.Logger).info("accepted before early stop", [])
    @hosting.builder(@core.AppName::parse("registry-completion"), [])
    |> @hosting.service("must-not-start", start=_ => hooks.val += 1)
    |> @hosting.build(_ => ())
  }, _ => fail("early stopped command ran"), signals=@hosting.SignalProbe::new(() => Some(kind)), completed=(outcome, selected) => {
    assert_true(outcome.stop_reason() is Signal(actual) && actual == kind)
    assert_eq(selected, kind.exit_code())
    assert_eq(hooks.val, 0)
    let report = captured.val.unwrap().status()
    assert_true(report.closed())
    assert_eq(report.accepted(), 1L)
    assert_eq(report.destinations()[0].written(), 1L)
    @async.sleep(1)
    // If reporting repeats, the controller sees more than one ok line.
    println("ok")
  })
}
