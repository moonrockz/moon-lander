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
/// Retain the first external signal for this run, including consuming readers.
/// Repeated reads cannot count OS signals; escalation belongs to the owner.
fn external_signal_reader(probe : @hosting.SignalProbe) -> () -> @hosting.SignalKind? {
  let observed : Ref[@hosting.SignalKind?] = Ref(None)
  () => {
    if observed.val is None {
      observed.val = probe.read()
    }
    observed.val
  }
}

///|
/// A step that the console driver runs after the host run and its failure
/// reports, before the process ends. It gets the exit code that the driver
/// selected and gives the exit code to use. The driver runs it one time, also
/// after a configuration or start failure, a shutdown timeout and a first
/// signal, protected from cancellation. With default handlers a second signal
/// ends the process at once; an external probe owner controls escalation.
/// A signal that arrives while it runs selects the signal code, because
/// a signal code comes first.
pub type Finalizer = async (@hosting.ExitCode) -> @hosting.ExitCode

///|
/// Report one returned host outcome after failure reports and finalization,
/// before console exit. The selected code includes finalizer and sink failures.
/// It is a snapshot: a later signal or a callback error can change process exit.
/// The driver runs this callback once, protected from cancellation. A callback
/// error changes selected success to failure and preserves nonzero codes.
/// Applications own their output schema and the callback's time budget.
pub type Completion = async (@hosting.RunOutcome, @hosting.ExitCode) -> Unit

///|
/// Run `finalize`, if any, protected from cancellation, and give the final exit
/// code: a signal that arrived meanwhile comes first. A finalizer that raises
/// keeps the selected code, except that a selected code 0 becomes code 1.
async fn finish(
  selected : @hosting.ExitCode,
  finalize : Finalizer?,
  signal : () -> @hosting.SignalKind?,
) -> @hosting.ExitCode {
  guard finalize is Some(step) else { return selected }
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
    Some(kind) => kind.exit_code()
    None => code
  }
}

///|
/// Report only after finalization. A missing callback adds no signal reads or
/// suspension. Keep the real outcome separate from later exit-code selection.
async fn report_completion(
  outcome : @hosting.RunOutcome,
  selected : @hosting.ExitCode,
  completed : Completion?,
  signal : () -> @hosting.SignalKind?,
) -> @hosting.ExitCode {
  guard completed is Some(report) else { return selected }
  let before = match signal() {
    Some(kind) => kind.exit_code()
    None => selected
  }
  let code = @async.protect_from_cancel(() => {
    try {
      report(outcome, before)
      before
    } catch {
      _ => if before == @hosting.ExitCode::success() {
        @hosting.ExitCode::failure()
      } else { before }
    }
  })
  match signal() {
    Some(kind) => kind.exit_code()
    None => code
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
