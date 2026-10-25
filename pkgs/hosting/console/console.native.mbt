///|
extern "C" fn stub_install() -> Int = "moonlander_console_install"

///|
extern "C" fn stub_signal_kind() -> Int = "moonlander_console_signal_kind"

///|
extern "C" fn libc_exit(code : Int) = "exit"

///|
/// Turn off the signal handling of the `moonbitlang/async` runtime, then
/// install the handlers of the C stub.
fn install() -> Unit raise ConsoleError {
  @signal.set_global_cancellation_signals([])
  guard stub_install() == 0 else { raise SignalHandlersUnavailable }
}

///|
/// One read of the value that the signal handler sets.
fn signal_kind() -> @hosting.SignalKind? {
  kind_of_code(stub_signal_kind())
}

///|
/// Run the host as a console program, then end the process with the exit code
/// of the run, through libc `exit`, which writes the buffered standard output.
/// It does not return after the run.
///
/// The driver handles SIGINT, SIGTERM and SIGQUIT on Linux and macOS, and
/// `CTRL_C_EVENT`, `CTRL_CLOSE_EVENT` and `CTRL_BREAK_EVENT` on Windows. The
/// first signal is a graceful stop with the reason `Signal(kind)`: the command
/// task is cancelled and all stop hooks run. A cancellation check sees the
/// signal at once, also in code that never suspends. A second signal ends the
/// process at once with its own exit code (130, 143 or 131), and no later hook
/// or event runs. The handlers are global, so run only one console host in a
/// process.
///
/// It raises `SignalHandlersUnavailable` before it reads configuration or runs a
/// hook when the handlers cannot be installed.
pub async fn[S] run(host : @hosting.Host[S], command : @hosting.Hook[S]) -> Unit {
  install()
  let outcome = @hosting.run(host, command, signals=@hosting.SignalProbe::new(signal_kind))
  libc_exit(outcome.exit_code().to_int())
}
