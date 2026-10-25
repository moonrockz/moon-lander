///|
/// A failure of the console driver before the host runs.
pub suberror ConsoleError {
  /// The driver cannot install its signal handlers or listeners.
  SignalHandlersUnavailable
}

///|
/// Text for people that names the failure.
pub fn ConsoleError::message(self : ConsoleError) -> String {
  match self {
    SignalHandlersUnavailable => "The console signal handlers cannot be installed"
  }
}

///|
/// The kind of a signal code from the native stub or the Node.js adapter:
/// 1 Interrupt, 2 Terminate, 3 Quit. Any other code is no signal. This is the
/// one place where a signal code becomes a `SignalKind`.
fn kind_of_code(code : Int) -> @hosting.SignalKind? {
  match code {
    1 => Some(Interrupt)
    2 => Some(Terminate)
    3 => Some(Quit)
    _ => None
  }
}
