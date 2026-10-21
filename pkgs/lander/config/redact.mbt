///|
/// The Morphir key-name fragments that mark a sensitive key.
pub fn default_redact_fragments() -> Array[String] {
  [
    "token",
    "password",
    "passwd",
    "secret",
    "credential",
    "api_key",
    "apikey",
    "private_key",
    "access_key",
  ]
}

///|
/// A copy of `value` with each sensitive subtree replaced by the text
/// `<redacted>`. A key is sensitive when its name, in lowercase with `-`
/// changed to `_`, holds a fragment. The default fragment list is Morphir's.
pub fn redact(
  value : ConfigValue,
  fragments~ : Array[String] = default_redact_fragments(),
) -> ConfigValue {
  redact_at(value, None, fragments)
}

///|
fn redact_at(
  value : ConfigValue,
  field_name : String?,
  fragments : Array[String],
) -> ConfigValue {
  if field_name is Some(name) && is_sensitive(name, fragments) {
    return string("<redacted>")
  }
  match value.ion.kind() {
    Struct(fields) => {
      let out = []
      for field in fields {
        let name = field.name().text().unwrap_or("")
        let child = redact_at({ ion: field.value() }, Some(name), fragments)
        out.push(@ion.Field::from_token(field.name(), child.ion))
      }
      {
        ion: @ion.Ion::from_fields(out).with_annotations(value.ion.annotations()),
      }
    }
    List(items) => {
      {
        ion: @ion.Ion::list(
            items.map(item => redact_at({ ion: item }, None, fragments).ion),
          )
          .with_annotations(value.ion.annotations()),
      }
    }
    Sexp(items) => {
      {
        ion: @ion.Ion::sexp(
            items.map(item => redact_at({ ion: item }, None, fragments).ion),
          )
          .with_annotations(value.ion.annotations()),
      }
    }
    _ => value
  }
}

///|
fn is_sensitive(name : String, fragments : Array[String]) -> Bool {
  let normalized = name.to_lower().replace_all(old="-", new="_")
  fragments.any(fragment => normalized.contains(fragment))
}
