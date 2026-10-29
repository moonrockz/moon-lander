///|
async fn main {
  check_api()
  for signal_stop in [false, true] {
    let signal : Ref[@library.SignalKind?] = Ref(None)
    let observed = []
    let host = @library.builder(@core.AppName::parse("registry-stop"), [])
      |> @library.build(_ => ())
    let outcome = @library.run(host, signals=@library.SignalProbe::new(() => signal.val), ctx => {
      let token = ctx.lifetime.stop_token()
      assert_false(poll(() => ctx.stop_requested() || ctx.lifetime.stop_requested() || token.stop_requested()))
      ignore(poll(() => {
        if signal_stop { signal.val = Some(Terminate) }
        else { ctx.lifetime.stop_application() }
        observed.push(ctx.stop_requested())
        observed.push(ctx.lifetime.stop_requested())
        observed.push(token.stop_requested())
        true
      }))
    })
    assert_eq(observed, [true, true, true])
    assert_eq(outcome.failures().length(), 0)
    if signal_stop {
      assert_true(outcome.stop_reason() is Signal(Terminate))
      assert_eq(outcome.exit_code().to_int(), 143)
    } else {
      assert_true(outcome.stop_reason() is Requested)
      assert_eq(outcome.exit_code().to_int(), 0)
    }
  }
  println("ok")
}
