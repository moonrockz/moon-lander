///|
priv enum OutputFormat { Human; MachineJson }

///|
priv enum CommandRequest { Help; Run(@moonx.Command) }

///|
priv struct LaunchOptions {
  format : OutputFormat
  request : CommandRequest
}

///|
priv enum UsageProblem {
  UnknownOption(String)
  MissingExecutable
  Executable(@moonx.ExecutableError)
  Arguments(@moonx.ArgumentsError)
}

///|
suberror CliUsageError {
  InvalidLaunchOptions(format~ : OutputFormat, problem~ : UsageProblem)
}

///|
/// Launcher options end at `--` or the first executable. Child options after
/// that boundary are opaque. A later leading --json still formats an earlier
/// unknown launcher option; child --json never selects parent reporting.
fn parse_options(args : Array[String]) -> LaunchOptions raise CliUsageError {
  let mut format = Human
  let mut help = false
  let mut unknown : String? = None
  let mut index = 0
  while index < args.length() {
    let input = args[index]
    if input == "--" { index += 1; break }
    if input == "--json" { format = MachineJson }
    else if input == "--help" || input == "-h" { help = true }
    else if input.has_prefix("-") {
      if unknown is None { unknown = Some(input) }
    } else { break }
    index += 1
  }
  if unknown is Some(input) { raise InvalidLaunchOptions(format~, problem=UnknownOption(input)) }
  if help { return { format, request: Help } }
  guard index < args.length() else { raise InvalidLaunchOptions(format~, problem=MissingExecutable) }
  let program = @moonx.Executable::parse(args[index]) catch {
    cause => raise InvalidLaunchOptions(format~, problem=Executable(cause))
  }
  let arguments = @moonx.Arguments::parse(args[index + 1:].to_owned()) catch {
    cause => raise InvalidLaunchOptions(format~, problem=Arguments(cause))
  }
  { format, request: Run(@moonx.Command::new(program, arguments)) }
}

///|
let usage = "Usage: moonx moonrockz/moon-lander-moonx/launch@VERSION [--json] [--] EXECUTABLE [ARG...]\n       moonx moonrockz/moon-lander-moonx/launch@VERSION --help [--json]"

///|
fn help_document() -> Json {
  { "schema_version": 1, "command": "moon-lander-moonx/launch", "package_version": package_version.text(), "kind": "help",
    "exit_status": 0, "usage": usage,
    "stdout_ownership": "Child output is opaque after startup; parent JSON reports only help, usage errors or a child that never started." }
}

///|
fn UsageProblem::document(self : UsageProblem) -> Json {
  match self {
    UnknownOption(input) => { "kind": "unknown-option", "input": input }
    MissingExecutable => { "kind": "missing-executable" }
    Executable(@moonx.ExecutableError::InvalidExecutable(input~, rule~)) => {
      "kind": "invalid-executable", "input": input,
      "rule": match rule { Empty => "empty"; ContainsNul => "contains-nul" },
    }
    Arguments(@moonx.ArgumentsError::ArgumentContainsNul(input~, index~)) => {
      "kind": "invalid-argument", "input": input, "index": index, "rule": "contains-nul",
    }
  }
}

///|
fn usage_document(problem : UsageProblem) -> Json {
  { "schema_version": 1, "command": "moon-lander-moonx/launch", "package_version": package_version.text(), "kind": "usage-error",
    "exit_status": 2, "reason": problem.document() }
}

///|
fn signal_name(signal : @moonx.LauncherSignal) -> String {
  match signal { Interrupt => "SIGINT"; Terminate => "SIGTERM"; Hangup => "SIGHUP"; Break => "SIGBREAK" }
}

///|
fn cancellation_document(cause : @moonx.CancellationCause) -> Json {
  match cause {
    Signal(signal) => { "kind": "signal", "signal": signal_name(signal) }
    Requested => { "kind": "requested" }
  }
}

///|
/// Only an outcome that proves no child started can produce a parent document.
fn startup_document(outcome : @moonx.LaunchOutcome) -> Json? {
  let reason = match outcome.result() {
    Started(_) => return None
    NotStarted(Cancelled(cause)) => cancellation_document(cause)
    NotStarted(Failed(failure)) => match failure {
      Materialization(error) => { "kind": "materialization-failed", "message": error.to_string() }
      NodeMissing(executable~, cause~) => {
        "kind": "node-missing", "executable": executable.to_string(), "message": cause.to_string(),
      }
      ProcessStart(error) => { "kind": "process-start-failed", "message": error.to_string() }
    }
  }
  Some({ "schema_version": 1, "command": "moon-lander-moonx/launch", "package_version": package_version.text(), "kind": "not-started",
    "exit_status": Json(outcome.selected_status().bits()), "reason": reason,
    "finalization_failure_count": outcome.finalization_failures().length() })
}
