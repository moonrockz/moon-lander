///|
/// Consume the parent's shared signal once, to verify retention through close.
extern "js" fn take_signal() -> Int =
  #|() => Atomics.exchange(globalThis.landerSignals, 0, 0)

///|
async fn main {
  @scenarios.run(
    SessionPoll,
    @env.get_env_var("LANDER_LOGGING_DIR").unwrap_or(""),
    signals=@hosting.SignalProbe::new(() => {
      match take_signal() {
        1 => Some(Interrupt)
        2 => Some(Terminate)
        _ => None
      }
    }),
  )
}
