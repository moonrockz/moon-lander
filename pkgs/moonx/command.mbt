///|
/// A rule that executable text can break.
pub enum ExecutableRule {
  Empty
  ContainsNul
} derive(Eq, Debug)

///|
pub extend ExecutableRule with Eq::{equal, not_equal}

///|
pub extend ExecutableRule with @debug.Debug::{to_repr}

///|
/// Invalid executable text, retained with its rule.
pub suberror ExecutableError {
  InvalidExecutable(input~ : String, rule~ : ExecutableRule)
} derive(Debug)

///|
pub extend ExecutableError with @debug.Debug::{to_repr}

///|
/// An executable path or PATH lookup name. It is nonempty and has no NUL.
pub struct Executable {
  priv text : String
} derive(Debug)

///|
pub extend Executable with @debug.Debug::{to_repr}

///|
/// Parse nonempty, NUL-free executable text without changing its spelling.
pub fn Executable::parse(input : String) -> Executable raise ExecutableError {
  guard !input.is_empty() else { raise InvalidExecutable(input~, rule=Empty) }
  guard !input.contains("\u{0}") else {
    raise InvalidExecutable(input~, rule=ContainsNul)
  }
  { text: input }
}

///|
/// Look up Node through the caller's PATH.
pub fn Executable::node() -> Executable { { text: "node" } }

///|
/// The original executable text.
pub fn Executable::to_string(self : Executable) -> String { self.text }

///|
/// An argument that an OS process cannot represent.
pub suberror ArgumentsError {
  ArgumentContainsNul(input~ : String, index~ : Int)
} derive(Debug)

///|
pub extend ArgumentsError with @debug.Debug::{to_repr}

///|
/// An immutable ordered argument array. Empty elements and delimiters are opaque.
pub struct Arguments {
  priv values : Array[String]
}

///|
/// Parse NUL-free arguments and retain a separate immutable array value.
pub fn Arguments::parse(inputs : Array[String]) -> Arguments raise ArgumentsError {
  for index, input in inputs {
    guard !input.contains("\u{0}") else { raise ArgumentContainsNul(input~, index~) }
  }
  { values: inputs.copy() }
}

///|
/// A valid empty argument list.
pub fn Arguments::empty() -> Arguments { { values: [] } }

///|
/// A fresh array. Mutating it cannot change these arguments.
pub fn Arguments::to_array(self : Arguments) -> Array[String] { self.values.copy() }

///|
/// Derive a valid argument list from two already parsed lists, without parsing
/// their elements again or sharing a mutable array.
pub fn Arguments::concat(self : Arguments, other : Arguments) -> Arguments {
  { values: self.values + other.values }
}

///|
/// A process invocation with no shell interpretation.
pub struct Command {
  priv program : Executable
  priv args : Arguments
}

///|
/// Construct an invocation from already parsed process inputs.
pub fn Command::new(program : Executable, args : Arguments) -> Command {
  { program, args }
}

///|
/// The selected executable.
pub fn Command::executable(self : Command) -> Executable { self.program }

///|
/// The immutable application argument list.
pub fn Command::arguments(self : Command) -> Arguments { self.args }

///|
/// A graceful-stop deadline must be positive and fit the runtime millisecond count.
pub suberror ShutdownGraceError {
  NonPositiveShutdownGrace(milliseconds~ : Int)
} derive(Debug)

///|
pub extend ShutdownGraceError with @debug.Debug::{to_repr}

///|
/// A positive grace period before forced child termination.
pub struct ShutdownGrace {
  priv milliseconds : Int
}

///|
/// Parse a positive runtime millisecond count.
pub fn ShutdownGrace::from_milliseconds(
  milliseconds : Int,
) -> ShutdownGrace raise ShutdownGraceError {
  guard milliseconds > 0 else { raise NonPositiveShutdownGrace(milliseconds~) }
  { milliseconds, }
}

///|
/// The standard five-second child grace period.
pub fn ShutdownGrace::standard() -> ShutdownGrace { { milliseconds: 5000 } }

///|
/// The validated runtime millisecond count.
pub fn ShutdownGrace::milliseconds(self : ShutdownGrace) -> Int { self.milliseconds }

///|
/// Work for the optional process driver. Every case contains valid immutable values.
pub(all) enum LaunchPlan {
  Process(Command)
  Node(NodeLaunch)
}
