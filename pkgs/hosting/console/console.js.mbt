///|
#external
priv type NodeAdapter

///|
#external
priv type SignalListeners

///|
extern "js" fn NodeAdapter::install_signals(self : NodeAdapter) -> SignalListeners =
  #|(adapter) => adapter.installSignals()

///|
extern "js" fn NodeAdapter::set_exit_code(self : NodeAdapter, code : Int) -> Unit =
  #|(adapter, code) => adapter.setExitCode(code)

///|
extern "js" fn SignalListeners::kind(self : SignalListeners) -> Int =
  #|(listeners) => listeners.kind()

///|
extern "js" fn SignalListeners::remove(self : SignalListeners) -> Unit =
  #|(listeners) => listeners.remove()

///|
extern "js" fn has_node_process() -> Bool =
  #|() => typeof process === "object" && process !== null && typeof process.on === "function" && typeof process.getBuiltinModule === "function"

///|
/// Run the host as a console program under Node.js or Bun, then set
/// `process.exitCode` to the exit code of the run. It returns after the run and
/// does not call `process.exit`, so the output that is still in a pipe is
/// written before the process ends.
///
/// The driver listens for SIGINT, SIGTERM and SIGQUIT on Linux and macOS, and
/// for SIGINT (Ctrl-C), SIGBREAK (Ctrl-Break) and SIGHUP (console close) on
/// Windows. The first signal is a graceful stop with the reason
/// `Signal(kind)`: the command task is cancelled and all stop hooks run. A
/// second signal calls `process.exit` at once with its own exit code (130, 143
/// or 131). A listener runs only when the JavaScript stack is empty, so a long
/// synchronous loop must call `@async.pause()` to see a signal. The driver
/// removes its listeners when the run ends.
///
/// It raises `SignalHandlersUnavailable` before it reads configuration or runs a
/// hook when the runtime has no Node.js `process`.
pub async fn[S] run(host : @hosting.Host[S], command : @hosting.Hook[S]) -> Unit {
  guard has_node_process() else { raise SignalHandlersUnavailable }
  let adapter = node_adapter()
  let listeners = adapter.install_signals()
  defer listeners.remove()
  let outcome = @hosting.run(host, command, signals=@hosting.SignalProbe::new(() => kind_of_code(listeners.kind())))
  adapter.set_exit_code(outcome.exit_code().to_int())
}
