///|
/// An immutable configuration value over an Ion value. Every format and source
/// gives values of this one type before the merge.
pub struct ConfigValue {
  priv ion : @ion.Ion
} derive(@debug.Debug)

///|
/// A source tree from an Ion value. The root must be a struct, else this
/// raises `InvalidRoot` with `origin`. A struct field name with no text, such
/// as an unresolved symbol ID, raises `Parse` for the Ion format. Two fields
/// with the same name in one struct raise `DuplicateKey`. The key path of a
/// field in a list item holds the struct field names only, because a key path
/// does not select list items.
pub fn ConfigValue::from_ion(
  ion : @ion.Ion,
  origin? : String = "value",
) -> ConfigValue raise ConfigError {
  let value = { ion, }
  value.check_root(origin)
  check_fields(ion, origin, [])
  value
}

///|
/// A source tree from a JSON value, through its Ion form. The rules of
/// `ConfigValue::from_ion` apply.
pub fn ConfigValue::from_json(
  json : Json,
  origin? : String = "value",
) -> ConfigValue raise ConfigError {
  ConfigValue::from_ion(@ion.Ion::Ion(json), origin~)
}

///|
/// The Ion value.
pub fn ConfigValue::to_ion(self : ConfigValue) -> @ion.Ion {
  self.ion
}

///|
/// Equality of the Ion data model. Struct fields compare as an unordered set.
pub impl Eq for ConfigValue with equal(self, other) {
  self.ion.equals(other.ion)
}

///|
pub extend ConfigValue with Eq::{equal, not_equal}

///|
pub extend ConfigValue with @debug.Debug::{to_repr}

///|
/// A string value.
pub fn string(text : String) -> ConfigValue {
  { ion: @ion.Ion::string(text) }
}

///|
/// An integer value.
pub fn int(value : Int64) -> ConfigValue {
  { ion: @ion.Ion::Ion(value) }
}

///|
/// A floating-point value.
pub fn float(value : Double) -> ConfigValue {
  { ion: @ion.Ion::float(value) }
}

///|
/// A Boolean value.
pub fn bool(value : Bool) -> ConfigValue {
  { ion: @ion.Ion::bool(value) }
}

///|
/// A list value.
pub fn list(items : Array[ConfigValue]) -> ConfigValue {
  { ion: @ion.Ion::list(items.map(item => item.ion)) }
}

///|
/// A struct value with the fields in the given order. When a name occurs more
/// than once, the last value wins at the position of the first.
pub fn fields(fields : Array[(String, ConfigValue)]) -> ConfigValue {
  let unique : Array[(String, ConfigValue)] = []
  for field in fields {
    match unique.search_by(existing => existing.0 == field.0) {
      Some(index) => unique[index] = field
      None => unique.push(field)
    }
  }
  {
    ion: @ion.Ion::from_fields(
      unique.map(field => @ion.field(field.0, field.1.ion)),
    ),
  }
}

///|
/// The Ion type name in lowercase, for example `struct` or `list`.
pub fn ConfigValue::type_name(self : ConfigValue) -> String {
  match self.ion.ion_type() {
    Null => "null"
    Bool => "bool"
    Int => "int"
    Float => "float"
    Decimal => "decimal"
    Timestamp => "timestamp"
    Symbol => "symbol"
    String => "string"
    Clob => "clob"
    Blob => "blob"
    List => "list"
    Sexp => "sexp"
    Struct => "struct"
  }
}

///|
/// The field at `name` when the value is a struct.
fn ConfigValue::field(self : ConfigValue, name : String) -> ConfigValue? {
  guard self.ion.kind() is Struct(fields) else { None }
  for field in fields {
    if field.name().text() == Some(name) {
      return Some({ ion: field.value() })
    }
  }
  None
}

///|
/// The value at the struct field names `names`, from this value down.
fn ConfigValue::at(self : ConfigValue, names : Array[String]) -> ConfigValue? {
  let mut value = self
  for name in names {
    guard value.field(name) is Some(next) else { return None }
    value = next
  }
  Some(value)
}

///|
/// Raise `InvalidRoot` when the value is not a struct.
fn ConfigValue::check_root(
  self : ConfigValue,
  origin : String,
) -> Unit raise ConfigError {
  guard self.ion.kind() is Struct(_) else {
    raise InvalidRoot(origin~, found=self.type_name())
  }
}

///|
/// Raise when a struct field name in `ion` has no text or occurs twice in one
/// struct. `path` holds the struct field names from the root to `ion`.
fn check_fields(
  ion : @ion.Ion,
  origin : String,
  path : Array[String],
) -> Unit raise ConfigError {
  match ion.kind() {
    Struct(fields) => {
      let seen : Set[String] = Set([])
      for field in fields {
        let token = field.name()
        guard token.text() is Some(name) else {
          let symbol = match token.sid() {
            Some(sid) => "$\{sid}"
            None => "symbol"
          }
          let place = if path.is_empty() {
            "the root"
          } else {
            KeyPath::{ names: path }.to_string()
          }
          raise Parse(
            format="Ion",
            origin~,
            message="the field name \{symbol} in \{place} has no text",
            line=None,
            column=None,
          )
        }
        let names = [..path, name]
        if seen.contains(name) {
          raise DuplicateKey(origin~, key={ names, })
        }
        seen.add(name)
        check_fields(field.value(), origin, names)
      }
    }
    List(items) | Sexp(items) =>
      for item in items {
        check_fields(item, origin, path)
      }
    _ => ()
  }
}
