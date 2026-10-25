///|
/// The first event that ended the run. Later requests keep this reason.
pub(all) enum StopReason {
  Completed
  Requested
  Signal(SignalKind)
  Embedder
  StartFailed(Error)
  Failed(Error)
}

///|
/// A signal whose identity the host knows.
pub(all) enum SignalKind { Interrupt; Terminate; Quit } derive(Eq, Debug)

///|
pub extend SignalKind with Eq::{equal, not_equal}

///|
pub extend SignalKind with @debug.Debug::{to_repr}

///|
/// The signal read of a console driver. `run` reads it in each cancellation
/// check and every 50 ms, and changes the first signal into a stop request
/// with the reason `Signal(kind)`. The read must be cheap and must not raise.
pub struct SignalProbe {
  priv request : () -> StopRequest?
}

///|
/// Make a probe from a read that gives the signal that asked the process to
/// stop, or `None` before a signal.
pub fn SignalProbe::new(read : () -> SignalKind?) -> SignalProbe {
  { request: () => read().map(kind => StopRequest::Signal(kind)) }
}

///|
/// A command or hook can raise this error to stop without a failure.
pub(all) suberror StopRequested

///|
priv struct EventHandlers {
  mut raised : Bool
  handlers : Array[() -> Unit]
}

///|
fn EventHandlers::new() -> EventHandlers { { raised: false, handlers: [] } }

///|
fn EventHandlers::register(self : EventHandlers, handler : () -> Unit) -> Unit {
  if self.raised { handler() } else { self.handlers.push(handler) }
}

///|
fn EventHandlers::raise_event(self : EventHandlers) -> Unit {
  if self.raised { return }
  self.raised = true
  let handlers = self.handlers.copy()
  self.handlers.clear()
  for handler in handlers { handler() }
}

///|
/// A handle to the events and stop state of one run. Only the host creates it.
pub struct Lifetime {
  priv started : EventHandlers
  priv stopping : EventHandlers
  priv stopped : EventHandlers
  priv mut reason : StopReason?
  priv mut request : StopRequest?
  priv mut signal : SignalKind?
  priv mut requested_code : ExitCode?
  priv mut exit_code : ExitCode?
  priv probes : Array[() -> StopRequest?]
  priv task_cancelled : Ref[() -> Bool]
  priv cancel_command : Ref[(() -> Unit)?]
}

///|
// The embedded driver is added in group 13. Remove when it creates a lifetime.
#warnings("-1")
fn Lifetime::new() -> Lifetime {
  { started: EventHandlers::new(), stopping: EventHandlers::new(), stopped: EventHandlers::new(),
    reason: None, request: None, signal: None, requested_code: None, exit_code: None, probes: [], task_cancelled: Ref(() => false), cancel_command: Ref(None) }
}

///|
/// Register a synchronous handler. After started, it runs at once, one time.
pub fn Lifetime::on_started(self : Lifetime, handler : () -> Unit) -> Unit { self.started.register(handler) }

///|
/// Register a synchronous handler. After stopping, it runs at once, one time.
pub fn Lifetime::on_stopping(self : Lifetime, handler : () -> Unit) -> Unit { self.stopping.register(handler) }

///|
/// Register a synchronous handler. After stopped, it runs at once, one time.
pub fn Lifetime::on_stopped(self : Lifetime, handler : () -> Unit) -> Unit { self.stopped.register(handler) }

///|
// The embedded driver is added in group 13. Remove when it raises events.
#warnings("-1")
fn Lifetime::raise_event(self : Lifetime, event : Event) -> Unit {
  match event {
    Started => self.started.raise_event()
    Stopping => self.stopping.raise_event()
    Stopped => self.stopped.raise_event()
  }
}

///|
fn Lifetime::request_stop(self : Lifetime, request : StopRequest, code : ExitCode?) -> Unit {
  if self.request is None {
    self.request = Some(request)
    self.requested_code = code
    if code is Some(_) { self.exit_code = code }
    if self.reason is None {
      self.reason = Some(match request { Requested => Requested; Signal(kind) => Signal(kind) })
    }
  }
  if request is Signal(signal) { self.signal = Some(signal) }
  if self.cancel_command.val is Some(cancel) { cancel() }
}

///|
/// Ask the host to stop. The first request keeps its optional exit code.
pub fn Lifetime::stop_application(self : Lifetime, exit_code? : ExitCode) -> Unit {
  self.request_stop(Requested, exit_code)
}

///|
/// Set the application exit code. Signals and failures take precedence.
/// The last set code or first request's explicit code wins.
pub fn Lifetime::set_exit_code(self : Lifetime, code : ExitCode) -> Unit { self.exit_code = Some(code) }

///|
/// The first event that ended the run, or None until an event ends it.
pub fn Lifetime::stop_reason(self : Lifetime) -> StopReason? { self.reason }

///|
/// A handle with the same stop checks as its lifetime.
/// During a run on native and js, read its checks inside an async task of the run.
pub struct StopToken { priv lifetime : Lifetime }

///|
/// Give a token for code that does not receive a Context.
pub fn Lifetime::stop_token(self : Lifetime) -> StopToken { { lifetime: self } }

///|
// Only `run` (native, js) registers a probe until the embedded driver of group
// 13 registers its embedder probe. Remove the override then.
#warnings("-1")
fn Lifetime::register_stop_probe(self : Lifetime, probe : () -> StopRequest?) -> Unit {
  self.probes.push(probe)
}

///|
fn Lifetime::probe_stop(self : Lifetime) -> Bool {
  for probe in self.probes {
    if probe() is Some(request) { self.request_stop(request, None) }
  }
  self.request is Some(_)
}

///|
/// Raise StopRequested when this token reports cancellation.
pub fn StopToken::check_cancelled(self : StopToken) -> Unit raise StopRequested {
  if self.cancelled() { raise StopRequested }
}

///|
/// Read the lifetime's stop state and the current task's cancellation state.
/// On native and js, read this check inside an async task of the run.
pub fn[S] Context::cancelled(self : Context[S]) -> Bool { self.lifetime.cancelled() }

///|
/// Raise StopRequested after a stop request or task cancellation.
pub fn[S] Context::check_cancelled(self : Context[S]) -> Unit raise StopRequested {
  if self.cancelled() { raise StopRequested }
}

///|
/// Read stop requests, registered probes and the current task's cancellation.
/// During a run on native and js, read this check inside an async task of the run.
/// Outside a running driver the token reads only its lifetime and probes.
pub fn StopToken::cancelled(self : StopToken) -> Bool {
  self.lifetime.cancelled()
}

///|
fn Lifetime::cancelled(self : Lifetime) -> Bool {
  self.probe_stop() || (self.task_cancelled.val)()
}
