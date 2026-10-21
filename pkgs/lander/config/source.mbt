///|
/// The selection of a source location or input. `Discover` uses the values
/// that a host or a source provider supplies, `Explicit` uses only the given
/// value, and `Skip` loads nothing.
pub(all) enum SourceSelection[T] {
  Discover
  Explicit(T)
  Skip
} derive(Eq, Debug)

///|
pub extend SourceSelection with Eq::{equal, not_equal}

///|
pub extend SourceSelection with @debug.Debug::{to_repr}

///|
/// An immutable configuration source: a kind, a display name, an optional
/// display priority, the input, and the key paths to exclude.
pub struct ConfigSource {
  priv kind : SourceKind
  priv name : String
  priv priority : Int?
  priv input : SourceInput
  priv excluded : Array[(KeyPath, Bool)]
}

///|
priv enum SourceInput {
  Value(ConfigValue)
  Path(String)
  Candidates(Array[String], String)
  NoInput
}

///|
/// The kind of the source.
pub fn ConfigSource::kind(self : ConfigSource) -> SourceKind {
  self.kind
}

///|
/// The display name of the source.
pub fn ConfigSource::name(self : ConfigSource) -> String {
  self.name
}

///|
/// An in-memory source from a value tree. The root must be a struct.
pub fn in_memory(
  value : ConfigValue,
  name? : String = "in-memory",
  priority? : Int,
) -> ConfigSource raise ConfigError {
  value.check_root(name)
  value_source(InMemory, name, priority, value)
}

///|
/// An in-memory source from flat key-path pairs, for example
/// `("ir.layout", @config.string("tree"))`. Pairs apply in list order with the
/// merge rules, so a later pair wins. Pair values keep their type.
pub fn in_memory_pairs(
  pairs : Array[(String, ConfigValue)],
  name? : String = "in-memory",
  priority? : Int,
) -> ConfigSource raise ConfigError {
  let mut value = fields([])
  for pair in pairs {
    let (text, leaf) = pair
    value = merge(value, nest(KeyPath::parse(text), leaf))
  }
  value_source(InMemory, name, priority, value)
}

///|
/// A defaults source from a JSON value, for example `Defaults::default().to_json()`.
/// The root must be an object.
pub fn ConfigSource::defaults(
  json : Json,
  name? : String = "defaults",
  priority? : Int,
) -> ConfigSource raise ConfigError {
  value_source(Defaults, name, priority, ConfigValue::from_json(json, origin=name))
}

///|
/// A defaults source from a value tree. The root must be a struct.
pub fn ConfigSource::defaults_value(
  value : ConfigValue,
  name? : String = "defaults",
  priority? : Int,
) -> ConfigSource raise ConfigError {
  value.check_root(name)
  value_source(Defaults, name, priority, value)
}

///|
/// A file source at an explicit path. A relative path joins the working
/// directory of the builder. The extension selects the registered format. The
/// load raises `FileNotFound` when the file does not exist. The name is the
/// path when no name is given.
pub fn ConfigSource::file(
  path : String,
  role? : FileRole = Explicit,
  name? : String,
  priority? : Int,
) -> ConfigSource {
  {
    kind: File(role),
    name: name.unwrap_or(path),
    priority,
    input: Path(path),
    excluded: [],
  }
}

///|
/// A file source over an explicit list of candidate files at one location.
/// No existing candidate gives the status `NotFound`, one loads it, and more
/// than one raises `Ambiguous` with `display`. A candidate exists when the
/// listing of its directory holds its exact name as a file. The name is
/// `display` when no name is given.
pub fn ConfigSource::candidates(
  paths : Array[String],
  display~ : String,
  role? : FileRole = Explicit,
  name? : String,
  priority? : Int,
) -> ConfigSource {
  {
    kind: File(role),
    name: name.unwrap_or(display),
    priority,
    input: Candidates(paths.copy(), display),
    excluded: [],
  }
}

///|
/// A source that loads nothing and reports the status `Skipped`. The name is
/// the report name of `kind` when no name is given.
pub fn ConfigSource::skipped(
  kind : SourceKind,
  name? : String,
  priority? : Int,
) -> ConfigSource {
  {
    kind,
    name: name.unwrap_or(kind_name(kind)),
    priority,
    input: NoInput,
    excluded: [],
  }
}

///|
/// A new source that removes the subtrees at `paths` after the parse and
/// before the merge. When `warn` is true, each removed key that the source held
/// adds a `KeyRemoved` warning to its report.
pub fn ConfigSource::exclude(
  self : ConfigSource,
  paths : Array[KeyPath],
  warn~ : Bool,
) -> ConfigSource {
  { ..self, excluded: [..self.excluded, ..paths.map(path => (path, warn))] }
}

///|
fn value_source(
  kind : SourceKind,
  name : String,
  priority : Int?,
  value : ConfigValue,
) -> ConfigSource {
  { kind, name, priority, input: Value(value), excluded: [] }
}

///|
/// A tree that holds `leaf` at `key`.
fn nest(key : KeyPath, leaf : ConfigValue) -> ConfigValue {
  key.names.rev_fold(init=leaf, (value, name) => fields([(name, value)]))
}

///|
/// `value` without the subtree at `names`, or `None` when it holds no value
/// there.
fn remove_key(value : ConfigValue, names : ArrayView[String]) -> ConfigValue? {
  guard value.ion.kind() is Struct(fields) && names is [name, .. rest] else {
    return None
  }
  guard fields.search_by(field => field.name().text() == Some(name))
    is Some(index) else {
    return None
  }
  let kept = fields.copy()
  if rest.is_empty() {
    kept.remove(index) |> ignore
  } else {
    guard remove_key({ ion: fields[index].value() }, rest) is Some(child) else {
      return None
    }
    kept[index] = @ion.Field::from_token(fields[index].name(), child.ion)
  }
  Some({
    ion: @ion.Ion::from_fields(kept).with_annotations(value.ion.annotations()),
  })
}
