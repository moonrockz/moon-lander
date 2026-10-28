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

///|
/// A step that the console driver runs after the host run and its failure
/// reports, before the process ends. It gets the exit code that the driver
/// selected and gives the exit code to use. The driver runs it one time, also
/// after a configuration or start failure, a shutdown timeout and a first
/// signal, protected from cancellation. A second signal still ends the process
/// at once. A signal that arrives while it runs selects the signal code, because
/// a signal code comes first.
pub type Finalizer = async (@hosting.ExitCode) -> @hosting.ExitCode

///|
/// Run `finalize`, if any, protected from cancellation, and give the final exit
/// code: a signal that arrived meanwhile comes first. A finalizer that raises
/// keeps the selected code, except that a selected code 0 becomes code 1.
async fn finish(
  selected : @hosting.ExitCode,
  finalize : Finalizer?,
  signal : () -> @hosting.SignalKind?,
) -> Int {
  guard finalize is Some(step) else { return selected.to_int() }
  let code = @async.protect_from_cancel(() => {
    step(selected) catch {
      _ =>
        if selected == @hosting.ExitCode::success() {
          @hosting.ExitCode::failure()
        } else {
          selected
        }
    }
  })
  match signal() {
    Some(kind) => kind.exit_code().to_int()
    None => code.to_int()
  }
}

///|
/// The exit code of the process after a run. A signal that arrived after the
/// last probe read of the run, for example during the stopped event, still
/// selects the signal code, because a signal code comes first.
fn selected_exit_code(outcome : @hosting.RunOutcome, late : @hosting.SignalKind?) -> @hosting.ExitCode {
  match late {
    Some(kind) => kind.exit_code()
    None => outcome.exit_code()
  }
}
