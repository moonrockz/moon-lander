///|
/// Test-only shared memory supplied by the parent launcher. Consume the first
/// value to exercise the driver's latch throughout cleanup and finalization.
extern "js" fn take_signal() -> Int =
  #|() => Atomics.exchange(globalThis.landerSignals, 0, 0)

///|
async fn main {
  let signals = @hosting.SignalProbe::new(() => {
    match take_signal() {
      1 => Some(Interrupt)
      2 => Some(Terminate)
      _ => None
    }
  })
  @scenarios.run(Poll, signals~, finalize=selected => {
    println("finalizer=begin")
    @async.sleep(50)
    println("drained=true")
    println("finalizer=end")
    // The retained signal must beat this replacement finalizer code.
    assert_eq(selected.to_int() == 130 || selected.to_int() == 143, true)
    @hosting.ExitCode::from_int(7)
  })
}
