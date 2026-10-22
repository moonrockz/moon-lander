///|
/// Whether a `$schema` value names the draft-07 dialect.
pub fn draft07_dialect(text : String) -> Bool {
  text == "http://json-schema.org/draft-07/schema" ||
  text == "http://json-schema.org/draft-07/schema#" ||
  text == "https://json-schema.org/draft-07/schema" ||
  text == "https://json-schema.org/draft-07/schema#"
}

///|
fn schema_shaped(value : @exact.Value) -> Bool {
  match value.kind() {
    @exact.Object(_) | @exact.Boolean(_) => true
    _ => false
  }
}

///|
/// The draft-07 subschema positions held by one keyword's value, as path
/// suffixes below that keyword. Only object and boolean values are positions;
/// literal keywords such as `const`, `enum` and `default` have none.
/// Shared by schema indexing and validation so both agree on what is a schema.
pub fn draft07_subschemas(
  keyword : String,
  value : @exact.Value,
) -> Array[(Array[String], @exact.Value)] {
  let result = []
  let push = fn(suffix, value) {
    if schema_shaped(value) {
      result.push((suffix, value))
    }
  }
  match keyword {
    "properties" | "definitions" | "patternProperties" | "dependencies" =>
      if value.kind() is @exact.Object(entries) {
        entries.sort_by((a, b) => a.0.lexical_compare(b.0))
        for (key, value) in entries {
          push([key], value)
        }
      }
    "allOf" | "anyOf" | "oneOf" | "items" =>
      if value.kind() is @exact.Array(items) {
        for i, value in items {
          push([i.to_string()], value)
        }
      } else if keyword == "items" {
        push([], value)
      }
    "additionalProperties"
    | "additionalItems"
    | "contains"
    | "propertyNames"
    | "if"
    | "then"
    | "else"
    | "not" => push([], value)
    _ => ()
  }
  result
}
