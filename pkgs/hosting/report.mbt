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
    if error is (@config.ConfigError::_ | UsageError(_)) { return usage_exit_code() }
  }
  if !failures.is_empty() || timed_out { return ExitCode::failure() }
  application.unwrap_or(ExitCode::success())
}

///|
// The embedded driver arrives in group 13; until then only native/js use this.
#warnings("-1")
fn report_text(name : @lander_core.AppName, error : Error) -> String {
  let message = match error {
    HostError::_ as e => e.message()
    UsageError::_ as e => e.message()
    ShutdownTimedOut::_ as e => e.message()
    @config.ConfigError::_ as e => e.message()
    e => e.to_string()
  }
  "\{name}: \{message}"
}
