///|
/// Shared checked values for OpenRPC documents and embedded schemas.
pub struct ComponentKey {
  text : String
} derive(Eq, Debug)

///|
pub fn ComponentKey::parse(
  text : String,
) -> Result[ComponentKey, @exact.Diagnostic] {
  if text.is_empty() ||
    !text
    .code_units()
    .iter()
    .all(c => {
      (c >= 48 && c <= 57) ||
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      c == 45 ||
      c == 46 ||
      c == 95
    }) {
    Err(
      @exact.Diagnostic::new(
        @exact.WrongType,
        "Component keys must match ^[a-zA-Z0-9.\\-_]+$",
      ),
    )
  } else {
    Ok({ text, })
  }
}

///|
/// Retain a component key exactly as read. Whether it follows a version's key
/// grammar is a validation result, not a reading failure.
pub fn ComponentKey::from_wire(text : String) -> ComponentKey {
  { text, }
}

///|
/// Whether the key matches `^[a-zA-Z0-9.\-_]+$`.
pub fn ComponentKey::is_conforming(self : ComponentKey) -> Bool {
  ComponentKey::parse(self.text) is Ok(_)
}

///|
pub fn ComponentKey::to_string(self : ComponentKey) -> String {
  self.text
}

///|
pub struct ExtensionName {
  text : String
} derive(Eq, Debug)

///|
pub fn ExtensionName::parse(
  text : String,
) -> Result[ExtensionName, @exact.Diagnostic] {
  if text.has_prefix("x-") {
    Ok({ text, })
  } else {
    Err(
      @exact.Diagnostic::new(
        @exact.WrongType,
        "Extension names must start with x-",
      ),
    )
  }
}

///|
pub fn ExtensionName::to_string(self : ExtensionName) -> String {
  self.text
}

///|
pub struct ErrorCode {
  number : @exact.Number
} derive(Eq, Debug)

///|
pub fn ErrorCode::from_number(
  number : @exact.Number,
) -> Result[ErrorCode, @exact.Diagnostic] {
  if number.is_integer() {
    Ok({ number, })
  } else {
    Err(
      @exact.Diagnostic::new(
        @exact.WrongType,
        "Error code must be a mathematical integer",
      ),
    )
  }
}

///|
pub fn ErrorCode::parse(token : String) -> Result[ErrorCode, @exact.Diagnostic] {
  match @exact.Number::parse(token) {
    Err(d) => Err(d)
    Ok(number) => ErrorCode::from_number(number)
  }
}

///|
pub fn ErrorCode::number(self : ErrorCode) -> @exact.Number {
  self.number
}

///|
pub struct Extensions {
  entries : Array[(ExtensionName, @exact.Value)]
} derive(Debug)

///|
pub fn Extensions::from_json(
  value : @exact.Value,
) -> Result[Extensions, @exact.Diagnostic] {
  guard value.kind() is @exact.Object(fields) else {
    return Err(
      @exact.Diagnostic::new(@exact.WrongType, "Extensions require an object"),
    )
  }
  let entries = []
  for (key, value) in fields {
    match ExtensionName::parse(key) {
      Ok(name) => entries.push((name, value))
      Err(d) =>
        return Err(@exact.Diagnostic::new(d.code(), d.message(), path=[key]))
    }
  }
  Ok({ entries, })
}

///|
pub fn Extensions::entries(
  self : Extensions,
) -> Array[(ExtensionName, @exact.Value)] {
  self.entries.copy()
}

///|
pub fn Extensions::get(
  self : Extensions,
  name : ExtensionName,
) -> @exact.Value? {
  for (key, value) in self.entries {
    if key == name {
      return Some(value)
    }
  }
  None
}

///|
pub fn Extensions::to_json(self : Extensions) -> @exact.Value {
  @exact.Value::object(self.entries.map(entry => (entry.0.text, entry.1))).unwrap()
}

///|
pub fn Extensions::empty() -> Extensions {
  { entries: [], }
}

///|
pub fn Extensions::from_entries(
  entries : Array[(ExtensionName, @exact.Value)],
) -> Result[Extensions, @exact.Diagnostic] {
  match @exact.Value::object(entries.map(entry => (entry.0.text, entry.1))) {
    Err(d) => Err(d)
    Ok(_) => Ok({ entries: entries.copy(), })
  }
}

///|
pub extend ComponentKey with Eq::{equal, not_equal}

///|
pub extend ComponentKey with @debug.Debug::{to_repr}

///|
pub extend ExtensionName with Eq::{equal, not_equal}

///|
pub extend ExtensionName with @debug.Debug::{to_repr}

///|
pub extend ErrorCode with Eq::{equal, not_equal}

///|
pub extend ErrorCode with @debug.Debug::{to_repr}

///|
pub extend Extensions with @debug.Debug::{to_repr}
