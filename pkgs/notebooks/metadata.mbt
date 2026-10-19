///|
/// A metadata shape or format-conversion failure.
pub(all) suberror MetadataError {
  ExpectedObject
  InvalidKey(String)
  NotJson(path~ : String, reason~ : String)
} derive(Eq, Debug)

///|
pub extend MetadataError with Eq::{equal, not_equal}

///|
pub extend MetadataError with @debug.Debug::{to_repr}

///|
pub fn MetadataError::message(self : MetadataError) -> String {
  match self {
    ExpectedObject => "metadata must be a non-null Ion struct"
    InvalidKey(message) => message
    NotJson(path~, reason~) => "\{path}: \{reason}"
  }
}

///|
/// Immutable Ion metadata with unique, textual top-level field names.
/// Import and export copy nested containers and annotations defensively.
struct Metadata {
  value : @ion.Ion
} derive(Debug)

///|
pub impl Eq for Metadata with fn equal(self, other) {
  self.value.equals(other.value)
}

///|
pub extend Metadata with Eq::{equal, not_equal}

///|
pub extend Metadata with @debug.Debug::{to_repr}

///|
fn copy_metadata_ion(value : @ion.Ion) -> @ion.Ion {
  let kind = match value.kind() {
    List(items) => @ion.IonValueKind::List(items.map(copy_metadata_ion))
    Sexp(items) => @ion.IonValueKind::Sexp(items.map(copy_metadata_ion))
    Struct(fields) => @ion.IonValueKind::Struct(fields.map(field => {
      @ion.Field::from_token(field.name(), copy_metadata_ion(field.value()))
    }))
    scalar => scalar
  }
  @ion.Ion(kind).with_annotations(value.annotations().copy())
}

///|
/// Construct from a JSON object. Use from_ion for the richer Ion data model.
/// This JSON input adapter retains the existing constructor's behavior.
pub fn Metadata::Metadata(value : Json) -> Metadata raise MetadataError {
  Metadata::from_ion(@ion.Ion(value))
}

///|
/// Require a non-null Ion struct with unique, textual top-level field names.
/// Nested Ion values retain their types, annotations and repeated fields.
pub fn Metadata::from_ion(value : @ion.Ion) -> Metadata raise MetadataError {
  guard value.kind() is Struct(fields) else { raise ExpectedObject }
  let seen = Map([])
  for field in fields {
    guard field.name().text() is Some(name) else {
      raise InvalidKey("metadata field names must have known text")
    }
    if seen.contains(name) {
      raise InvalidKey("duplicate metadata field: \{name}")
    }
    seen[name] = true
  }
  { value: copy_metadata_ion(value), }
}

///|
pub fn Metadata::empty() -> Metadata {
  { value: @ion.Ion::from_fields([]), }
}

///|
/// Look up a field as an independent Ion value. Typed nulls are present;
/// an absent field is None. No format conversion is performed.
pub fn Metadata::get(self : Metadata, key : String) -> @ion.Ion? {
  if self.value.kind() is Struct(fields) {
    for field in fields {
      if field.name().text() == Some(key) {
        return Some(copy_metadata_ion(field.value()))
      }
    }
  }
  None
}

///|
/// Explicit JSON lookup. Raise NotJson if the selected value needs Ion's
/// richer types; None still means the key is absent.
pub fn Metadata::get_json(self : Metadata, key : String) -> Json? raise MetadataError {
  self.get(key).map(value => metadata_json(value, "$." + key))
}

///|
pub fn Metadata::keys(self : Metadata) -> ReadOnlyArray[String] {
  match self.value.kind() {
    Struct(fields) => ReadOnlyArray::from_iter(fields.iter().map(field => {
      field.name().text().unwrap()
    }))
    _ => []
  }
}

///|
pub fn Metadata::is_empty(self : Metadata) -> Bool {
  match self.value.kind() {
    Struct(fields) => fields.is_empty() && !self.value.has_annotations()
    _ => false
  }
}

///|
/// Export a defensive copy of the native Ion value, retaining every type.
pub fn Metadata::to_ion(self : Metadata) -> @ion.Ion {
  copy_metadata_ion(self.value)
}

///|
/// Export independent JSON. Reject annotations, typed nulls, non-finite
/// floats, symbols, timestamps, lob values, sexps and repeated struct fields.
/// Integers and decimals retain their exact numeric spelling.
pub fn Metadata::to_json(self : Metadata) -> Json raise MetadataError {
  metadata_json(self.value, "$")
}

///|
fn metadata_json(value : @ion.Ion, path : String) -> Json raise MetadataError {
  if value.has_annotations() {
    raise NotJson(path~, reason="annotations require Ion")
  }
  match value.kind() {
    Struct(fields) => {
      let result = Map([])
      for field in fields {
        guard field.name().text() is Some(name) else {
          raise NotJson(path~, reason="field name has no known text")
        }
        if result.contains(name) {
          raise NotJson(path~, reason="repeated field: \{name}")
        }
        result[name] = metadata_json(field.value(), "\{path}.\{name}")
      }
      Json::object(result)
    }
    List(items) => Json::array(items.mapi((i, item) => {
      metadata_json(item, "\{path}[\{i}]")
    }))
    Decimal(decimal) => {
      // Keep exponent notation compact rather than expanding large powers
      // into millions of zeroes during automatic DIB format selection.
      let text = decimal.to_ion_string().replace_all(old="d", new="e")
      let text = if text.has_suffix(".") { text + "0" } else { text }
      let number = @json.parse(text) catch {
        _ => raise NotJson(path~, reason="invalid decimal representation")
      }
      guard number is Number(value, ..) else {
        raise NotJson(path~, reason="expected a decimal number")
      }
      Json::number(value, repr=text)
    }
    Null(@ion.IonType::Null) | Bool(_) | String(_) | Int(_) =>
      @ion_json.to_json(value) catch {
        error => raise NotJson(path~, reason=error.message())
      }
    Float(number) if !number.is_inf() && !number.is_nan() =>
      Json::number(number)
    _ => raise NotJson(path~, reason="value requires Ion")
  }
}
