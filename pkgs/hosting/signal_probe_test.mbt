///|
test "a public signal probe read preserves typed signal values" {
  let signal : Ref[@hosting.SignalKind?] = Ref(None)
  let probe = @hosting.SignalProbe::new(() => signal.val)
  assert_eq(probe.read(), None)
  signal.val = Some(Terminate)
  assert_eq(probe.read(), Some(Terminate))
  signal.val = Some(Interrupt)
  assert_eq(probe.read(), Some(Interrupt))
}
