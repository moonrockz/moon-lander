///|
test "process status preserves the complete Windows bit pattern" {
  for bits in [0U, 1U, 255U, 256U, 0x7fffffffU, 0x80000000U, 0xc000013aU, 0xffffffffU] {
    let status = @moonx.ProcessStatus::from_bits(bits)
    assert_eq(status.bits(), bits)
    assert_eq(status.to_int().reinterpret_as_uint(), bits)
    assert_eq(status.is_success(), bits == 0U)
  }
  assert_eq(@moonx.ProcessStatus::success().bits(), 0U)
  assert_eq(@moonx.ProcessStatus::failure().bits(), 1U)
}

///|
test "completion separates startup state and selected status with owned issue arrays" {
  let failures : Array[@moonx.FinalizationFailure] = []
  let outcome = @moonx.LaunchOutcome::new(
    NotStarted(Cancelled(Signal(Interrupt))),
    @moonx.ProcessStatus::from_bits(130U), failures,
  )
  failures.push(Finalizer(Failure("later input mutation")))
  let copy = outcome.finalization_failures()
  copy.push(Finalizer(Failure("later output mutation")))
  assert_eq(outcome.finalization_failures().length(), 0)
  assert_eq(outcome.selected_status().bits(), 130U)
  match outcome.result() {
    NotStarted(Cancelled(Signal(Interrupt))) => ()
    _ => fail("Lost the typed startup cancellation")
  }
}
