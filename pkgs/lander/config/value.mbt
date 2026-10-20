///|
/// An immutable configuration value over an Ion value. Every format and source
/// gives values of this one type before the merge.
pub struct ConfigValue {
  priv ion : @ion.Ion
} derive(@debug.Debug)

///|
/// Wrap an Ion value.
pub fn ConfigValue::from_ion(ion : @ion.Ion) -> ConfigValue {
  { ion, }
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
/// A struct value with the fields in the given order.
pub fn fields(fields : Array[(String, ConfigValue)]) -> ConfigValue {
  {
    ion: @ion.Ion::from_fields(
      fields.map(field => @ion.field(field.0, field.1.ion)),
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
/// Raise `InvalidRoot` when the value is not a struct.
fn ConfigValue::check_root(
  self : ConfigValue,
  origin : String,
) -> Unit raise ConfigError {
  guard self.ion.kind() is Struct(_) else {
    raise InvalidRoot(origin~, found=self.type_name())
  }
}
