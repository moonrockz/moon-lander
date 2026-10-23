///|
/// A fault in the program that sets up a host: a name, a code or a service set
/// that breaks its rules.
pub(all) suberror HostError {
  /// The text is not a valid application name.
  InvalidAppName(text~ : String, reason~ : String)
  /// The text is not a valid service name.
  InvalidServiceName(text~ : String, reason~ : String)
  /// The builder already has a service with this name.
  DuplicateService(name~ : ServiceName)
  /// The number is not in the exit code range 0 to 255.
  InvalidExitCode(code~ : Int)
} derive(Debug)

///|
pub extend HostError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn HostError::message(self : HostError) -> String {
  match self {
    InvalidAppName(text~, reason~) =>
      "Invalid application name \{text.escape()}: \{reason}"
    InvalidServiceName(text~, reason~) =>
      "Invalid service name \{text.escape()}: \{reason}"
    DuplicateService(name~) =>
      "The host already has a service named \{name.to_string().escape()}"
    InvalidExitCode(code~) =>
      "Invalid exit code \{code}: an exit code is in the range 0 to 255"
  }
}

///|
/// The name of an application. It starts with an ASCII letter, and holds only
/// ASCII letters, digits, `-` and `_`. So it is safe in file and directory
/// names, and it gives a valid environment-variable prefix.
pub struct AppName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend AppName with Eq::{equal, not_equal}

///|
pub extend AppName with Hash::{hash, hash_combine}

///|
pub extend AppName with @debug.Debug::{to_repr}

///|
/// Parse an application name, for example `acme` or `my-tool`.
pub fn AppName::parse(text : String) -> AppName raise HostError {
  fn invalid(reason : String) -> HostError {
    InvalidAppName(text~, reason~)
  }

  guard text.iter().head() is Some(first) else {
    raise invalid("the name is empty")
  }
  guard is_ascii_letter(first) else {
    raise invalid("the name must start with an ASCII letter")
  }
  for char in text {
    guard is_name_char(char) else {
      raise invalid(
        "the character \{char.to_string().escape()} is not allowed; use ASCII letters, digits, '-' and '_'",
      )
    }
  }
  { text, }
}

///|
/// The name as text, which `AppName::parse` reads back to an equal name.
pub impl Show for AppName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend AppName with Show::{output, to_string}

///|
/// The name of a hosted service. It starts with an ASCII letter, and holds only
/// ASCII letters, digits, `.`, `-` and `_`. So a report can show it as it is,
/// with no whitespace, control or direction characters.
pub struct ServiceName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend ServiceName with Eq::{equal, not_equal}

///|
pub extend ServiceName with Hash::{hash, hash_combine}

///|
pub extend ServiceName with @debug.Debug::{to_repr}

///|
/// Parse a service name, for example `db`, `telemetry` or `db.primary`.
pub fn ServiceName::parse(text : String) -> ServiceName raise HostError {
  fn invalid(reason : String) -> HostError {
    InvalidServiceName(text~, reason~)
  }

  guard text.iter().head() is Some(first) else {
    raise invalid("the name is empty")
  }
  guard is_ascii_letter(first) else {
    raise invalid("the name must start with an ASCII letter")
  }
  for char in text {
    guard is_name_char(char) || char == '.' else {
      raise invalid(
        "the character \{char.to_string().escape()} is not allowed; use ASCII letters, digits, '.', '-' and '_'",
      )
    }
  }
  { text, }
}

///|
/// The name as text, which `ServiceName::parse` reads back to an equal name.
pub impl Show for ServiceName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ServiceName with Show::{output, to_string}

///|
fn is_ascii_letter(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
}

///|
/// An ASCII letter, an ASCII digit, `-` or `_`.
fn is_name_char(char : Char) -> Bool {
  is_ascii_letter(char) || (char >= '0' && char <= '9') || char == '-' || char == '_'
}
