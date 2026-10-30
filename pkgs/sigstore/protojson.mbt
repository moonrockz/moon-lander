///|
/// A protobuf JSON document that breaks a rule: the field path and the rule.
priv suberror Shape {
  Shape(String, String)
}

///|
/// The fields of a protobuf JSON object, checked against the names that the
/// message has, as sigstore-go reads them: the lowerCamelCase name or the proto
/// field name, no unknown field, no field twice, and `null` as absent.
priv struct Fields {
  path : String
  values : Map[String, Json]
}

///|
/// The proto field name of a lowerCamelCase JSON name.
fn snake_case(name : String) -> String {
  let out = StringBuilder()
  for char in name {
    if char >= 'A' && char <= 'Z' {
      out.write_char('_')
      out.write_char((char.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(char)
    }
  }
  out.to_string()
}

///|
fn fields(json : Json, path : String, names : Array[String]) -> Fields raise Shape {
  guard json is Object(map) else { raise Shape(path, "expected an object") }
  let values : Map[String, Json] = Map([])
  for key, value in map {
    let name = if names.contains(key) {
      key
    } else {
      match names.iter().find_first(name => snake_case(name) == key) {
        Some(name) => name
        None => raise Shape(join(path, key), "unknown field")
      }
    }
    guard !values.contains(name) else { raise Shape(join(path, name), "field is repeated") }
    if value is Null {
      continue
    }
    values[name] = value
  }
  { path, values }
}

///|
fn join(path : String, name : String) -> String {
  if path.is_empty() {
    name
  } else {
    "\{path}.\{name}"
  }
}

///|
fn Fields::at(self : Fields, name : String) -> String {
  join(self.path, name)
}

///|
fn Fields::has(self : Fields, name : String) -> Bool {
  self.values.contains(name)
}

///|
fn Fields::get(self : Fields, name : String) -> Json? {
  self.values.get(name)
}

///|
fn Fields::object(
  self : Fields,
  name : String,
  names : Array[String],
) -> Fields? raise Shape {
  match self.get(name) {
    Some(json) => Some(fields(json, self.at(name), names))
    None => None
  }
}

///|
fn Fields::require_object(
  self : Fields,
  name : String,
  names : Array[String],
) -> Fields raise Shape {
  guard self.object(name, names) is Some(found) else {
    raise Shape(self.at(name), "field is required")
  }
  found
}

///|
fn Fields::string(self : Fields, name : String) -> String? raise Shape {
  match self.get(name) {
    Some(String(text)) => Some(text)
    Some(_) => raise Shape(self.at(name), "expected a string")
    None => None
  }
}

///|
fn Fields::require_string(self : Fields, name : String) -> String raise Shape {
  guard self.string(name) is Some(text) && !text.is_empty() else {
    raise Shape(self.at(name), "field is required")
  }
  text
}

///|
/// A `bytes` field: base64 in either alphabet. An absent field is empty.
fn Fields::bytes(self : Fields, name : String) -> Bytes raise Shape {
  match self.string(name) {
    Some(text) =>
      @encoding.decode_base64(text) catch {
        _ => raise Shape(self.at(name), "not base64")
      }
    None => b""
  }
}

///|
fn Fields::require_bytes(self : Fields, name : String) -> Bytes raise Shape {
  let bytes = self.bytes(name)
  guard !bytes.is_empty() else { raise Shape(self.at(name), "field is required") }
  bytes
}

///|
/// An `int64` field: a JSON string or an integral number. An absent field is 0.
fn Fields::int64(self : Fields, name : String) -> Int64 raise Shape {
  let text = match self.get(name) {
    Some(String(text)) => text
    Some(Number(value, repr~)) =>
      match repr {
        Some(text) => text
        None => {
          guard value == value.floor() && value.abs() < 9007199254740992.0 else {
            raise Shape(self.at(name), "not an integer")
          }
          return value.to_int64()
        }
      }
    Some(_) => raise Shape(self.at(name), "expected an integer")
    None => return 0L
  }
  let mut digits = 0
  for index, char in text {
    if char >= '0' && char <= '9' {
      digits += 1
    } else if !(index == 0 && char == '-') {
      raise Shape(self.at(name), "not an integer")
    }
  }
  guard digits > 0 else { raise Shape(self.at(name), "not an integer") }
  @string.parse_int64(text) catch {
    _ => raise Shape(self.at(name), "not a 64-bit integer")
  }
}

///|
fn Fields::array(self : Fields, name : String) -> Array[Json] raise Shape {
  match self.get(name) {
    Some(Array(items)) => items
    Some(_) => raise Shape(self.at(name), "expected an array")
    None => []
  }
}

///|
/// An enum field: its name, or the name of its number in `names`.
fn Fields::enum_name(
  self : Fields,
  name : String,
  names : Array[String],
) -> String? raise Shape {
  match self.get(name) {
    Some(String(text)) => Some(text)
    Some(Number(value, ..)) => {
      let index = value.to_int()
      guard index.to_double() == value && index >= 0 && index < names.length() else {
        raise Shape(self.at(name), "unknown enum number")
      }
      Some(names[index])
    }
    Some(_) => raise Shape(self.at(name), "expected an enum")
    None => None
  }
}

///|
/// Parse a JSON document as protobuf JSON expects: duplicate keys fail and
/// numbers keep their text.
fn parse_json(text : StringView) -> Json raise Shape {
  @json.parse(text, reject_duplicate_keys=true, preserve_number_repr=true) catch {
    err => raise Shape("", "not JSON: \{err}")
  }
}
