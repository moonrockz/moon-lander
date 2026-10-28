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
extern "js" fn NodeAdapter::exit_after(self : NodeAdapter, code : Int, ms : Int) -> Unit =
  #|(adapter, code, ms) => adapter.exitAfter(code, ms)

///|
/// After a graceful signal stop, the time that the event loop has to become
/// empty before the driver ends the process with `process.exit`.
let signal_exit_grace : Int = 2000

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
/// does not call `process.exit` at once, so the output that is still in a pipe
/// is written before the process ends. After a graceful signal stop, it ends the
/// process with `process.exit` when the event loop is not empty 2 seconds later,
/// for example because a service left a timer or a socket open.
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
/// `finalize` runs after the run and its failure reports, before the driver
/// sets the exit code and returns. See `Finalizer`.
///
/// It raises `SignalHandlersUnavailable` before it reads configuration or runs a
/// hook when the runtime has no Node.js `process`.
pub async fn[S] run(
  host : @hosting.Host[S],
  command : @hosting.Hook[S],
  finalize? : Finalizer,
) -> Unit {
  guard has_node_process() else { raise SignalHandlersUnavailable }
  let adapter = node_adapter()
  let listeners = adapter.install_signals()
  defer listeners.remove()
  errdefer adapter.set_exit_code(1)
  let outcome = @hosting.run(host, command, signals=@hosting.SignalProbe::new(() => kind_of_code(listeners.kind())))
  let selected = selected_exit_code(outcome, kind_of_code(listeners.kind()))
  let code = finish(selected, finalize, () => kind_of_code(
    listeners.kind(),
  ))
  let signal = kind_of_code(listeners.kind())
  adapter.set_exit_code(code)
  // A signal asks the process to end. A handle that a service left open must
  // not keep it running, so the process ends after a grace time. The timer
  // does not keep the event loop open, so a process that has nothing left to
  // do ends first, after Node.js writes the output that is still in a pipe.
  if signal is Some(_) {
    adapter.exit_after(code, signal_exit_grace)
  }
}
