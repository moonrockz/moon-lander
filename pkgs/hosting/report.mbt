///|
/// An application command can raise this error for invalid usage.
pub(all) suberror UsageError { UsageError(String) }

///|
/// The usage error text for people or a custom report.
pub fn UsageError::message(self : UsageError) -> String {
  let UsageError(message) = self
  message
}

///|
/// The injected configuration tree does not answer these file requests.
/// Only the host makes this error; callers can inspect each request and path.
pub suberror FileTreeError {
  IncompleteFileTree(requests~ : Array[@config.FileRequest])
}

///|
/// Text for people that names every requested path.
pub fn FileTreeError::message(self : FileTreeError) -> String {
  let IncompleteFileTree(requests~) = self
  let paths = requests.map(request => match request {
    ListDir(path) | ReadFile(path) => path.to_string()
  })
  "Incomplete configuration file tree; requested paths: " + paths.join(", ")
}

///|
/// The six hooks of a hosted service.
pub(all) enum HookPhase { Starting; Start; Started; Stopping; Stop; Stopped } derive(Eq, Debug)

///|
pub extend HookPhase with Eq::{equal, not_equal}

///|
pub extend HookPhase with @debug.Debug::{to_repr}

///|
/// The hook name as it is in `@hosting.service`, for example `start`.
pub impl Show for HookPhase with output(self, logger) {
  logger.write_string(match self {
    Starting => "starting"
    Start => "start"
    Started => "started"
    Stopping => "stopping"
    Stop => "stop"
    Stopped => "stopped"
  })
}

///|
pub extend HookPhase with Show::{output, to_string}

///|
/// A hook or the command suspended in `run_embedded` on wasm or wasm-gc. That
/// driver has no event loop, so it cannot resume suspended work. Only the host
/// makes this error.
// Only `run_embedded` (wasm, wasm-gc) makes these. Remove when the build system
// can limit a constructor to targets.
#warnings("-6")
pub suberror SuspendError {
  HookSuspended(service~ : ServiceName, phase~ : HookPhase)
  CommandSuspended
}

///|
/// Text for people that names the step and tells how to correct it.
pub fn SuspendError::message(self : SuspendError) -> String {
  let step = match self {
    HookSuspended(service~, phase~) => "The \{phase} hook of service \{service.to_string().escape()}"
    CommandSuspended => "The command"
  }
  step + " suspended. On wasm and wasm-gc, hooks and the command must not wait: remove the wait, or run the host on native or js"
}

///|
/// The stop phase used its full time budget. Only the host makes this error.
pub suberror ShutdownTimedOut { ShutdownTimedOut(@lander_core.TimeLimit) }

///|
/// Text for people that names the shutdown time limit.
pub fn ShutdownTimedOut::message(self : ShutdownTimedOut) -> String {
  let ShutdownTimedOut(limit) = self
  "Shutdown timed out after \{limit}"
}

///|
/// The portable process exit code for this signal.
pub fn SignalKind::exit_code(self : SignalKind) -> ExitCode {
  { code: match self { Interrupt => 130; Terminate => 143; Quit => 131 } }
}

///|
fn usage_exit_code() -> ExitCode { { code: 2 } }

///|
/// Failure phases share code 1; configuration and usage errors in any phase
/// outrank them. This function performs no I/O and never parses an exit code.
fn select_exit_code(signal : SignalKind?, failures : Array[Error], timed_out : Bool, application : ExitCode?) -> ExitCode {
  if signal is Some(kind) { return kind.exit_code() }
  for error in failures {
    if error is (@config.ConfigError::_ | UsageError(_) | IncompleteFileTree(..)) { return usage_exit_code() }
  }
  if !failures.is_empty() || timed_out { return ExitCode::failure() }
  application.unwrap_or(ExitCode::success())
}

///|
fn report_text(name : @lander_core.AppName, error : Error) -> String {
  let message = match error {
    HostError::_ as e => e.message()
    WorkingDirectoryError::_ as e => e.message()
    UsageError::_ as e => e.message()
    FileTreeError::_ as e => e.message()
    SuspendError::_ as e => e.message()
    ShutdownTimedOut::_ as e => e.message()
    @config.ConfigError::_ as e => e.message()
    e => e.to_string()
  }
  "\{name}: \{message}"
}
