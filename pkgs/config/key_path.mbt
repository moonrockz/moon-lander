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
/// Parse the dotted text form, for example `ir.strict_mode`. A name that
/// contains `.` or `"` uses double quotes, for example `servers."eu.west".port`.
/// In a quoted name, `\"` gives `"` and `\\` gives `\`.
pub fn KeyPath::parse(text : String) -> KeyPath raise ConfigError {
  fn invalid(reason : String) -> ConfigError {
    InvalidKeyPath(text~, reason~)
  }

  if text.is_empty() {
    raise invalid("the key path is empty")
  }
  let chars = Array::from_iter(text.iter())
  let names = []
  let mut index = 0
  while true {
    let name = StringBuilder()
    if index < chars.length() && chars[index] == '"' {
      index += 1
      let mut closed = false
      while index < chars.length() {
        let char = chars[index]
        index += 1
        if char == '"' {
          closed = true
          break
        }
        if char == '\\' {
          guard index < chars.length() &&
            (chars[index] == '"' || chars[index] == '\\') else {
            raise invalid("a quoted name allows only the escapes \\\" and \\\\")
          }
          name.write_char(chars[index])
          index += 1
        } else {
          name.write_char(char)
        }
      }
      if !closed {
        raise invalid("a quoted name has no closing quote")
      }
      if index < chars.length() && chars[index] != '.' {
        raise invalid("a quoted name must end at a dot or at the end")
      }
    } else {
      while index < chars.length() && chars[index] != '.' {
        if chars[index] == '"' {
          raise invalid("a quote can only start a name")
        }
        name.write_char(chars[index])
        index += 1
      }
    }
    let name = name.to_string()
    if name.is_empty() {
      raise invalid("a name in the key path is empty")
    }
    names.push(name)
    if index == chars.length() {
      break
    }
    // Skip the dot. A dot at the end gives an empty name in the next pass.
    index += 1
  }
  { names, }
}

///|
/// A key path from field names, from the root down. The list and each name
/// must not be empty.
pub fn KeyPath::from_names(names : Array[String]) -> KeyPath raise ConfigError {
  let path = { names: names.copy() }
  if names.is_empty() {
    raise InvalidKeyPath(text="", reason="the key path is empty")
  }
  if names.contains("") {
    raise InvalidKeyPath(
      text=path.to_string(),
      reason="a name in the key path is empty",
    )
  }
  path
}

///|
/// The field names, from the root down.
pub fn KeyPath::names(self : KeyPath) -> Array[String] {
  self.names.copy()
}

///|
/// The text form, which `KeyPath::parse` reads back to an equal key path.
pub impl Show for KeyPath with output(self, logger) {
  for index, name in self.names {
    if index > 0 {
      logger.write_char('.')
    }
    write_name(logger, name)
  }
}

///|
pub extend KeyPath with Show::{output, to_string}

///|
/// Write `name` bare, or in double quotes when it contains `.` or `"`.
fn write_name(logger : &Logger, name : String) -> Unit {
  if !(name.contains(".") || name.contains("\"")) {
    logger.write_string(name)
    return
  }
  logger.write_char('"')
  for char in name {
    if char == '"' || char == '\\' {
      logger.write_char('\\')
    }
    logger.write_char(char)
  }
  logger.write_char('"')
}
