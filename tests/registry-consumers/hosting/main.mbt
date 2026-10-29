///|
fn check_api() -> Unit raise {
  assert_eq(@library.ExitCode::success().to_int(), 0)
  assert_eq(@library.SignalProbe::new(() => Some(Terminate)).read(), Some(Terminate))
  let stop : (@library.Lifetime) -> Unit = lifetime => lifetime.stop_from_embedder()
  ignore(stop)
  ignore(@library.RunOutcome::stop_reason)
}
