///|
/// Compile the unchanged logger factory with the additive probe argument.
async fn legacy() -> Unit {
  @bridge.run(@sinks.SessionSettings::standard(), _ => fail("factory failure"),
    (_ : @hosting.Context[Unit]) => (), signals=@hosting.SignalProbe::new(() => None))
}

///|
async fn main {
  ignore(legacy)
  let completed = Ref(false)
  let captured : Ref[@runtime.Session?] = Ref(None)
  let failed = try {
    @bridge.run_with_session(@sinks.SessionSettings::standard(), session => {
      captured.val = Some(session)
      (session.logger() : &@lander_logging.Logger).info("accepted by public bridge", [])
      fail("factory failure")
    }, (_ : @hosting.Context[Unit]) => (), signals=@hosting.SignalProbe::new(() => None), completed=(_, _) => completed.val = true)
    false
  } catch { _ => true }
  assert_true(failed)
  assert_false(completed.val)
  let session = captured.val.unwrap()
  let report = session.status()
  assert_true(report.closed())
  assert_eq(report.accepted(), 1L)
  assert_eq(report.destinations()[0].written(), 1L)
  assert_eq(report, session.close())
  assert_eq(report, session.close())
  println("ok")
}
