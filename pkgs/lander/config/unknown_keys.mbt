///|
/// What `bind_or` does with a configured key that the bound value does not
/// hold. `FromJson` ignores unknown keys, so a misspelled key has no effect
/// unless the check is on.
pub(all) enum UnknownKeys {
  /// Ignore unknown keys, as `FromJson` does. The default.
  Allow
  /// Fail for each configured key that the `ToJson` form of the bound value
  /// does not hold.
  Reject
  /// As `Reject`, but also accept the listed key paths, relative to the bound
  /// section, and the keys below them. Use it for a decoder that accepts a key
  /// that its encoder does not write, for example an alias.
  RejectExcept(Array[String])
} derive(Eq, Debug)

///|
pub extend UnknownKeys with Eq::{equal, not_equal}

///|
pub extend UnknownKeys with @debug.Debug::{to_repr}

///|
/// The detail of a failure at an unknown key.
let unknown_key_detail = "is an unknown key"

///|
/// Raise one `Validation` error with a failure for each key of `section`, the
/// configured section at `key`, that `written`, the `ToJson` form of the bound
/// value, does not hold. A key that a listed path names, or a key below it, is
/// accepted. The check goes into tables and list items, and it stops where the
/// written form has no table or list of the same length, because the type
/// then reads that value in its own way.
fn Config::check_unknown_keys(
  self : Config,
  key : KeyPath,
  section : ConfigValue,
  written : Json,
  unknown : UnknownKeys,
) -> Unit raise ConfigError {
  let accepted = match unknown {
    Allow => return
    Reject => []
    RejectExcept(keys) => keys.map(text => KeyPath::parse(text).names)
  }
  let failures : Array[BindFailure] = []
  fn walk(
    steps : Array[DecodeStep],
    names : Array[String],
    configured : ConfigValue,
    written : Json,
  ) -> Unit {
    match (configured.ion.kind(), written) {
      (Struct(fields), Object(written_fields)) =>
        for field in fields {
          guard field.name().text() is Some(name) else { continue }
          let child_names = [..names, name]
          if accepted.iter().any(listed => starts_with(child_names, listed)) {
            continue
          }
          let child_steps : Array[DecodeStep] = [..steps, Field(name)]
          match written_fields.get(name) {
            Some(child) =>
              walk(child_steps, child_names, { ion: field.value() }, child)
            None => {
              let path = decode_path_below(Some(key), child_steps)
              failures.push({
                at: [{ path, blame: self.blame(path) }],
                detail: unknown_key_detail,
              })
            }
          }
        }
      (List(items) | Sexp(items), Array(written_items)) if items.length() ==
        written_items.length() =>
        for index, item in items {
          walk([..steps, Index(index)], names, { ion: item }, written_items[index])
        }
      _ => ()
    }
  }

  walk([], [], section, written)
  if !failures.is_empty() {
    raise Validation(failures~)
  }
}

///|
/// Whether `names` starts with every name of `prefix`, in order.
fn starts_with(names : Array[String], prefix : Array[String]) -> Bool {
  prefix.length() <= names.length() && names[:prefix.length()] == prefix[:]
}
