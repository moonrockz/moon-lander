///|
/// Which signal or console event asked the process to stop.
pub(all) enum SignalKind {
  /// SIGINT, or `CTRL_C_EVENT` on Windows.
  Interrupt
  /// SIGTERM, or `CTRL_CLOSE_EVENT` on Windows.
  Terminate
  /// SIGQUIT, or `CTRL_BREAK_EVENT` on Windows.
  Quit
} derive(Eq, Debug)

///|
pub extend SignalKind with Eq::{equal, not_equal}

///|
pub extend SignalKind with @debug.Debug::{to_repr}

///|
/// The exit code of a stop by this signal: 130, 143 or 131.
pub fn SignalKind::exit_code(self : SignalKind) -> Int {
  match self {
    Interrupt => 130
    Terminate => 143
    Quit => 131
  }
}

///|
extern "C" fn stub_install() -> Int = "moonlander_console_install"

///|
extern "C" fn stub_signal_kind() -> Int = "moonlander_console_signal_kind"

///|
/// Turn off the signal handling of the `moonbitlang/async` runtime and install
/// the console signal handlers. On Linux and macOS they handle SIGINT, SIGTERM
/// and SIGQUIT; on Windows `CTRL_C_EVENT`, `CTRL_BREAK_EVENT` and
/// `CTRL_CLOSE_EVENT`. The first signal sets the stop request. A second signal
/// ends the process at once with its exit code. Gives `false` when the
/// handlers cannot be installed.
pub fn install() -> Bool {
  @signal.set_global_cancellation_signals([])
  stub_install() == 0
}

///|
/// Whether a signal asked the process to stop. One read of a value that the
/// signal handler sets, so synchronous code can call it often.
pub fn stop_requested() -> Bool {
  stub_signal_kind() != 0
}

///|
/// The signal that asked the process to stop, or `None` before a signal.
pub fn signal_kind() -> SignalKind? {
  match stub_signal_kind() {
    1 => Some(Interrupt)
    2 => Some(Terminate)
    3 => Some(Quit)
    _ => None
  }
}
