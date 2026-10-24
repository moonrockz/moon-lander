///|
/// One step of a decode path after the key path: a list index or a field name.
pub(all) enum DecodeStep {
  Field(String)
  Index(Int)
} derive(Eq, Debug)

///|
pub extend DecodeStep with Eq::{equal, not_equal}

///|
pub extend DecodeStep with @debug.Debug::{to_repr}

///|
/// The path of a value that failed to decode. `key` holds the leading names up
/// to the first list index, and `None` is the root of the bound tree. `suffix`
/// is empty or starts with an `Index` step.
pub(all) struct DecodePath {
  key : KeyPath?
  suffix : Array[DecodeStep]
} derive(Eq, Debug)

///|
pub extend DecodePath with Eq::{equal, not_equal}

///|
pub extend DecodePath with @debug.Debug::{to_repr}

///|
/// The text form, for example `targets[1].level` or `servers."eu.west".port`.
/// A field name uses the quote rule of `KeyPath`. A path with no key and no
/// suffix gives `(root)`.
pub impl Show for DecodePath with output(self, logger) {
  match self.key {
    Some(key) => key.output(logger)
    None => if self.suffix.is_empty() { logger.write_string("(root)") }
  }
  for index, step in self.suffix {
    match step {
      Index(item) => logger.write_string("[\{item}]")
      Field(name) => {
        if self.key is Some(_) || index > 0 {
          logger.write_char('.')
        }
        write_name(logger, name)
      }
    }
  }
}

///|
pub extend DecodePath with Show::{output, to_string}

///|
/// The sources to blame for a value that failed to decode.
pub(all) enum Blame {
  /// The sources that set this leaf or list, in merge order. Never empty.
  Set(Array[Origin])
  /// The key is a table. The sources that set keys in it, in merge order.
  Table(Array[Origin])
  /// The value came from the bind default.
  Default
  /// No source sets this key.
  Unset
} derive(Eq, Debug)

///|
pub extend Blame with Eq::{equal, not_equal}

///|
pub extend Blame with @debug.Debug::{to_repr}

///|
/// A decode path and the sources to blame for it.
pub(all) struct Located {
  path : DecodePath
  blame : Blame
} derive(Eq, Debug)

///|
pub extend Located with Eq::{equal, not_equal}

///|
pub extend Located with @debug.Debug::{to_repr}

///|
/// A binding failure: the decoder or validation detail and the paths that it
/// names. `at` holds one or more paths and is never empty.
pub(all) struct BindFailure {
  at : Array[Located]
  detail : String
} derive(Eq, Debug)

///|
pub extend BindFailure with Eq::{equal, not_equal}

///|
pub extend BindFailure with @debug.Debug::{to_repr}

///|
/// Text for people: one line for each path, `<path>: <detail> (<blame text>)`.
fn BindFailure::lines(self : BindFailure) -> String {
  if self.at.is_empty() {
    return self.detail
  }
  self.at
  .map(located => "\{located.path}: \{self.detail} (\{blame_text(located.blame)})")
  .join("\n")
}

///|
/// Text for people that names the sources to blame.
fn blame_text(blame : Blame) -> String {
  match blame {
    Set(origins) => "set in \{origins_text(origins)}"
    Table([]) => "empty table, no source sets keys in it"
    Table(origins) => "table set in \{origins_text(origins)}"
    Default => "from the bind default"
    Unset => "not set by any source"
  }
}

///|
fn origins_text(origins : Array[Origin]) -> String {
  origins.map(origin_text).join(", ")
}
