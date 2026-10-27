///|
/// A configuration failure. Each case is one failure class, so a caller can
/// match it without a string compare. The core, conventions, and binding
/// capabilities raise these cases and have no error type of their own.
pub(all) suberror ConfigError {
  /// A format could not parse the text of a source.
  Parse(
    format~ : String,
    origin~ : String,
    message~ : String,
    line~ : Int?,
    column~ : Int?
  )
  /// The text uses a YAML feature that the profile does not allow.
  UnsupportedYaml(origin~ : String, feature~ : String, line~ : Int, column~ : Int)
  /// The root of a source tree is not a struct.
  InvalidRoot(origin~ : String, found~ : String)
  /// A struct in a source tree holds the same field name twice.
  DuplicateKey(origin~ : String, key~ : KeyPath)
  /// An explicit file does not exist.
  FileNotFound(path~ : String)
  /// No registered format reads the extension of a file.
  UnsupportedFormat(path~ : String, extensions~ : Array[String])
  /// More than one candidate file exists at one location.
  Ambiguous(display~ : String, location~ : String, candidates~ : Array[String])
  /// The text is not a valid key path.
  InvalidKeyPath(text~ : String, reason~ : String)
  /// The text of a file-tree path breaks a path rule.
  InvalidFilePath(text~ : String, rule~ : FilePathRule)
  /// An environment variable name gives a key path with an empty segment.
  InvalidEnvKey(variable~ : String)
  /// A merge-by-key list item has no key value, or repeats a key value.
  MergeKey(key~ : KeyPath, index~ : Int, source~ : String)
  /// A secret reference has a payload of the wrong shape.
  InvalidSecret(key~ : KeyPath, origin~ : String, reason~ : String)
  /// No value is at the key path.
  KeyNotFound(key~ : KeyPath)
  /// A value could not be written in the format.
  Render(format~ : String, key~ : KeyPath, reason~ : String)
  /// A source has a lower priority than the source before it.
  SourceOrder(
    source~ : String,
    priority~ : Int,
    previous~ : String,
    previous_priority~ : Int
  )
  /// The start directory of discovery is outside the boundary directory.
  OutsideBoundary(start~ : String, boundary~ : String)
  /// An environment name breaks the name rules.
  InvalidEnvironmentName(name~ : String, reason~ : String)
  /// No project in the workspace matches the selector.
  UnknownProject(selector~ : String, workspace~ : String)
  /// More than one project matches the selector by name.
  AmbiguousProject(selector~ : String, matches~ : Array[String])
  /// A bound value failed to decode.
  Decode(failure~ : BindFailure)
  /// A bound value failed validation.
  Validation(failures~ : Array[BindFailure])
} derive(Eq, Debug)

///|
pub extend ConfigError with Eq::{equal, not_equal}

///|
pub extend ConfigError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the failure. Paths show as the error holds
/// them; the host adapter gives them in the `/` form.
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
    UnsupportedYaml(origin~, feature~, line~, column~) =>
      "Unsupported YAML feature in \{origin} at line \{line}, column \{column}: \{feature}"
    InvalidRoot(origin~, found~) =>
      "The configuration root of \{origin} must be a struct, not a \{found}"
    DuplicateKey(origin~, key~) =>
      "Duplicate configuration key \{key} in \{origin}"
    FileNotFound(path~) => "Configuration file not found: \{path}"
    UnsupportedFormat(path~, extensions~) => {
      let registered = if extensions.is_empty() {
        "no format is registered"
      } else {
        "registered extensions: \{extensions.join(", ")}"
      }
      "No configuration format reads \{path}; \{registered}"
    }
    Ambiguous(display~, candidates~, ..) =>
      "Ambiguous \{display} configuration; found: \{candidates.join(", ")}"
    InvalidKeyPath(text~, reason~) =>
      "Invalid configuration key path \"\{text}\": \{reason}"
    InvalidFilePath(text~, rule~) =>
      "Invalid file path \"\{text}\": \{rule.describe()}"
    InvalidEnvKey(variable~) =>
      "Invalid configuration environment variable \{variable}: a key segment is empty"
    MergeKey(key~, index~, source~) =>
      "Cannot merge list \{key} by key: item \{index} from \{source} has no key value or repeats one"
    InvalidSecret(key~, origin~, reason~) =>
      "Invalid secret reference \{key} in \{origin}: \{reason}"
    KeyNotFound(key~) => "Configuration key not found: \{key}"
    Render(format~, key~, reason~) =>
      "Cannot write configuration key \{key} as \{format}: \{reason}"
    SourceOrder(source~, priority~, previous~, previous_priority~) =>
      "Configuration source \{source} has priority \{priority}, lower than priority \{previous_priority} of the source \{previous} before it"
    OutsideBoundary(start~, boundary~) =>
      "The start directory \{start} is outside the boundary \{boundary}"
    InvalidEnvironmentName(name~, reason~) =>
      "Invalid environment name \"\{name}\": \{reason}"
    UnknownProject(selector~, workspace~) =>
      "No project in the workspace \{workspace} matches \{selector}"
    AmbiguousProject(selector~, matches~) =>
      "More than one project matches \{selector}: \{matches.join(", ")}; select a member by its path"
    Decode(failure~) => failure.lines()
    Validation(failures~) => failures.map(BindFailure::lines).join("\n")
  }
}
