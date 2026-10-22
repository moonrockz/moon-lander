///|
/// A broken validation rule: the paths of the values it names, relative to
/// the bound section, and a detail text. An empty `at` names the section.
pub(all) struct Violation {
  at : Array[Array[DecodeStep]]
  detail : String
} derive(Eq, Debug)

///|
pub extend Violation with Eq::{equal, not_equal}

///|
pub extend Violation with @debug.Debug::{to_repr}

///|
/// Validation rules that run after decoding. `validate` is pure: it returns
/// every broken rule and never raises. A type with no rules uses the default,
/// which returns no violations.
pub(open) trait Validate {
  validate(Self) -> Array[Violation] = _
}

///|
impl Validate with validate(_) {
  []
}

///|
/// A violation that names one field of the section for each name in
/// `fields`, or the section itself when `fields` is empty. A rule over two
/// fields names both, so the error shows the source of each value.
pub fn violation(fields : Array[String], detail : String) -> Violation {
  { at: fields.map(field => [Field(field)]), detail }
}

///|
/// The violations of the value in `field`, with each path moved below
/// `field`. A violation of the whole nested value names `field`.
pub fn nested(field : String, found : Array[Violation]) -> Array[Violation] {
  below(Field(field), found)
}

///|
fn below(step : DecodeStep, found : Array[Violation]) -> Array[Violation] {
  found.map(violation => {
    let at = if violation.at.is_empty() {
      [[step]]
    } else {
      violation.at.map(path => [step, ..path])
    }
    { ..violation, at }
  })
}

///|
/// The violations of each value, below its key.
pub impl[T : Validate] Validate for Map[String, T] with validate(self) {
  let found = []
  for key, value in self {
    found.append(below(Field(key), T::validate(value)))
  }
  found
}

///|
/// The violations of each item, below its list index.
pub impl[T : Validate] Validate for Array[T] with validate(self) {
  let found = []
  for index, item in self {
    found.append(below(Index(index), T::validate(item)))
  }
  found
}

///|
/// The violations of the value, or none for `None`.
pub impl[T : Validate] Validate for T? with validate(self) {
  match self {
    Some(value) => T::validate(value)
    None => []
  }
}

///|
/// A bound and validated value, the key path of its section, and the instance
/// name of a named option. An options value exists only after decoding and
/// validation succeed.
pub struct Options[T] {
  value : T
  key : KeyPath
  name : String?
}

///|
/// Validate `value`, the section at `key` of `config`, and give it as an
/// options value. Each violation becomes a failure with its full decode path
/// and the sources to blame, and all of them raise one `Validation`. The
/// value comes first, so `validated` ends a binding pipeline:
/// `config |> bind_or("ir", default) |> validated(config, "ir")`.
pub fn[T : Validate] validated(
  value : T,
  config : Config,
  key : String,
  name? : String,
) -> Options[T] raise ConfigError {
  let path = KeyPath::parse(key)
  let found = T::validate(value)
  if !found.is_empty() {
    raise Validation(failures=found.map(violation => {
      let paths = if violation.at.is_empty() { [[]] } else { violation.at }
      let at = paths.map(steps => {
        let path = decode_path_below(Some(path), steps)
        { path, blame: config.blame(path) }
      })
      { at, detail: violation.detail }
    }))
  }
  { value, key: path, name }
}

///|
/// Bind the section at `key` and validate it: `bind`, then `validated`.
pub fn[T : FromJson + Validate] options(
  config : Config,
  key : String,
) -> Options[T] raise ConfigError {
  let value : T = bind(config, key)
  validated(value, config, key)
}
