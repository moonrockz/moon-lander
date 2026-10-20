///|
/// A path to a value in a configuration tree: a non-empty list of non-empty
/// field names. Name matches are exact and case-sensitive. A key path does not
/// select list items.
pub struct KeyPath {
  priv names : Array[String]
} derive(Eq, Hash, Debug)

///|
pub extend KeyPath with Eq::{equal, not_equal}

///|
pub extend KeyPath with Hash::{hash, hash_combine}

///|
pub extend KeyPath with @debug.Debug::{to_repr}

///|
/// Parse the dotted text form, for example `ir.strict_mode`.
pub fn KeyPath::parse(text : String) -> KeyPath raise ConfigError {
  if text.is_empty() {
    raise InvalidKeyPath(text~, reason="the key path is empty")
  }
  let names = []
  for name in text.split(".") {
    if name.is_empty() {
      raise InvalidKeyPath(text~, reason="a name in the key path is empty")
    }
    names.push(name.to_owned())
  }
  { names, }
}

///|
/// The field names, from the root down.
pub fn KeyPath::names(self : KeyPath) -> Array[String] {
  self.names.copy()
}

///|
pub impl Show for KeyPath with output(self, logger) {
  logger.write_string(self.names.join("."))
}

///|
pub extend KeyPath with Show::{output, to_string}
