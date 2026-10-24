///|
/// The rule of an application name that a text breaks.
pub enum AppNameRule {
  /// The name is empty.
  Empty
  /// The first character is not an ASCII letter.
  FirstNotAsciiLetter
  /// The name holds a character that is not an ASCII letter, an ASCII digit,
  /// `-` or `_`.
  CharNotAllowed(Char)
} derive(Eq, Debug)

///|
pub extend AppNameRule with Eq::{equal, not_equal}

///|
pub extend AppNameRule with @debug.Debug::{to_repr}

///|
/// A text that is not a valid application name. Callers can match the cases,
/// but only `AppName::parse` makes them.
pub suberror AppNameError {
  /// The text `text` breaks the rule `rule`.
  InvalidAppName(text~ : String, rule~ : AppNameRule)
} derive(Debug)

///|
pub extend AppNameError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn AppNameError::message(self : AppNameError) -> String {
  let InvalidAppName(text~, rule~) = self
  let reason = match rule {
    Empty => "the name is empty"
    FirstNotAsciiLetter => "the name must start with an ASCII letter"
    CharNotAllowed(char) =>
      "the character \{char.to_string().escape()} is not allowed; use ASCII letters, digits, '-' and '_'"
  }
  "Invalid application name \{text.escape()}: \{reason}"
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
pub fn AppName::parse(text : String) -> AppName raise AppNameError {
  guard text.iter().head() is Some(first) else {
    raise InvalidAppName(text~, rule=Empty)
  }
  guard is_ascii_letter(first) else {
    raise InvalidAppName(text~, rule=FirstNotAsciiLetter)
  }
  for char in text {
    guard is_name_char(char) else {
      raise InvalidAppName(text~, rule=CharNotAllowed(char))
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
fn is_ascii_letter(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
}

///|
/// An ASCII letter, an ASCII digit, `-` or `_`.
fn is_name_char(char : Char) -> Bool {
  is_ascii_letter(char) || (char >= '0' && char <= '9') || char == '-' || char == '_'
}
