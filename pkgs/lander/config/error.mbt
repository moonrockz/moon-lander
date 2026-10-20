///|
/// A configuration failure. Each case is one failure class, so a caller can
/// match it without a string compare.
pub(all) suberror ConfigError {
  /// A format could not parse the text of a source.
  Parse(
    format~ : String,
    origin~ : String,
    message~ : String,
    line~ : Int?,
    column~ : Int?
  )
  /// The root of a source tree is not a struct.
  InvalidRoot(origin~ : String, found~ : String)
  /// A struct in a source tree holds the same field name twice.
  DuplicateKey(origin~ : String, key~ : KeyPath)
  /// The text is not a valid key path.
  InvalidKeyPath(text~ : String, reason~ : String)
  /// No value is at the key path.
  KeyNotFound(KeyPath)
  /// A value could not be written in the format.
  Render(format~ : String, key~ : KeyPath, reason~ : String)
} derive(Eq, Debug)

///|
pub extend ConfigError with Eq::{equal, not_equal}

///|
pub extend ConfigError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the failure.
pub fn ConfigError::message(self : ConfigError) -> String {
  match self {
    Parse(format~, origin~, message~, line~, column~) => {
      let position = match (line, column) {
        (Some(line), Some(column)) => " at line \{line}, column \{column}"
        (Some(line), None) => " at line \{line}"
        _ => ""
      }
      "Failed to parse \{format} configuration \{origin}\{position}: \{message}"
    }
    InvalidRoot(origin~, found~) =>
      "The configuration root of \{origin} must be a struct, not a \{found}"
    DuplicateKey(origin~, key~) =>
      "Duplicate configuration key \{key} in \{origin}"
    InvalidKeyPath(text~, reason~) =>
      "Invalid configuration key path \"\{text}\": \{reason}"
    KeyNotFound(key) => "Configuration key not found: \{key}"
    Render(format~, key~, reason~) =>
      "Cannot write configuration key \{key} as \{format}: \{reason}"
  }
}
