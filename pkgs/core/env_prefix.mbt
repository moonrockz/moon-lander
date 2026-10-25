///|
/// The rule of an environment-variable prefix that a text breaks.
pub enum EnvPrefixRule {
  /// The prefix is empty.
  Empty
  /// The first character is not an ASCII letter or underscore.
  FirstNotLetterOrUnderscore
  /// The prefix holds a character that is not an ASCII letter, an ASCII digit,
  /// or `_`.
  CharNotAllowed(Char)
} derive(Eq, Debug)

///|
pub extend EnvPrefixRule with Eq::{equal, not_equal}

///|
pub extend EnvPrefixRule with @debug.Debug::{to_repr}

///|
/// A text that is not an environment-variable name. Callers can match the cases,
/// but only `EnvPrefix::parse` makes them.
pub suberror EnvPrefixError {
  /// The text `text` breaks the rule `rule`.
  InvalidEnvPrefix(text~ : String, rule~ : EnvPrefixRule)
} derive(Debug)

///|
pub extend EnvPrefixError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn EnvPrefixError::message(self : EnvPrefixError) -> String {
  let InvalidEnvPrefix(text~, rule~) = self
  let reason = match rule {
    Empty => "the prefix is empty"
    FirstNotLetterOrUnderscore => "the prefix must start with an ASCII letter or underscore"
    CharNotAllowed(char) =>
      "the character \{char.to_string().escape()} is not allowed; use ASCII letters, digits and '_'"
  }
  "Invalid environment-variable prefix \{text.escape()}: \{reason}"
}

///|
/// A variable prefix starting with an ASCII letter or underscore, followed
/// by ASCII letters, digits and underscores.
pub struct EnvPrefix {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend EnvPrefix with Eq::{equal, not_equal}

///|
pub extend EnvPrefix with Hash::{hash, hash_combine}

///|
pub extend EnvPrefix with @debug.Debug::{to_repr}

///|
/// Parse an environment-variable prefix, for example `ACME` or `MY_TOOL`.
pub fn EnvPrefix::parse(text : String) -> EnvPrefix raise EnvPrefixError {
  guard text.iter().head() is Some(first) else {
    raise InvalidEnvPrefix(text~, rule=Empty)
  }
  guard is_ascii_letter(first) || first == '_' else {
    raise InvalidEnvPrefix(text~, rule=FirstNotLetterOrUnderscore)
  }
  for char in text {
    guard is_ascii_letter(char) || is_digit(char) || char == '_' else {
      raise InvalidEnvPrefix(text~, rule=CharNotAllowed(char))
    }
  }
  { text, }
}

///|
/// The name as text, which `EnvPrefix::parse` reads back to an equal name.
pub impl Show for EnvPrefix with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend EnvPrefix with Show::{output, to_string}

///|
/// Derive the default prefix from a valid application name. This cannot fail.
pub fn EnvPrefix::from_app_name(name : AppName) -> EnvPrefix {
  { text: name.to_string().to_upper().replace_all(old="-", new="_") }
}
