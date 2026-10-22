///|
/// Decode the section at `key` into a `T`. `key` is the text form of a key
/// path, for example `ir` or `servers."eu.west"`. A section that no source sets
/// decodes as `null`, so an `Option` target gives `None`. A decode failure
/// raises `Decode` with the decode path, the decoder detail, and the sources to
/// blame. A secret reference in the section raises `Decode`, and binding never
/// resolves it. Binding does not change the configuration.
pub fn[T : FromJson] bind(config : Config, key : String) -> T raise ConfigError {
  let path = KeyPath::parse(key)
  match config.get(path) {
    Some(value) => {
      config.check_no_secret(Some(path), value)
      decode(config, Some(path), section_json(config, Some(path), value))
    }
    None => decode(config, Some(path), Json::null())
  }
}

///|
/// Decode the section at `key` into a `T`, as `bind` does.
pub fn[T : FromJson] Config::bind(self : Config, key : String) -> T raise ConfigError {
  bind(self, key)
}

///|
/// Decode the full configuration into a `T`. Decode paths start at the root.
pub fn[T : FromJson] bind_root(config : Config) -> T raise ConfigError {
  config.check_no_secret(None, config.root)
  decode(config, None, section_json(config, None, config.root))
}

///|
/// The detail of a decode error at a secret reference.
let secret_detail = "is a secret reference; bind it as SecretRef with bind_with"

///|
/// Raise `Decode` at the first secret reference in `value`, the section at
/// `key`. `FromJson` reads a reference as an ordinary table, and binding can
/// not tell which keys a type reads, so every reference in the section fails.
/// The check never resolves the reference.
fn Config::check_no_secret(
  self : Config,
  key : KeyPath?,
  value : ConfigValue,
) -> Unit raise ConfigError {
  guard self.secret_syntax is Standard else { return }
  guard secret_steps(value, self.secret_syntax) is Some(steps) else { return }
  let path = decode_path_below(key, steps)
  raise Decode(failure={
    at: [{ path, blame: self.blame(path) }],
    detail: secret_detail,
  })
}

///|
/// The steps from `value` to its first secret reference, in field and list
/// order, or `None` when it holds none.
fn secret_steps(
  value : ConfigValue,
  syntax : SecretSyntax,
) -> Array[DecodeStep]? {
  if is_secret_reference(value, syntax) {
    return Some([])
  }
  match value.ion.kind() {
    Struct(fields) =>
      for field in fields {
        guard field.name().text() is Some(name) else { continue }
        if secret_steps({ ion: field.value() }, syntax) is Some(steps) {
          return Some([Field(name), ..steps])
        }
      }
    List(items) | Sexp(items) =>
      for index, item in items {
        if secret_steps({ ion: item }, syntax) is Some(steps) {
          return Some([Index(index), ..steps])
        }
      }
    _ => ()
  }
  None
}

///|
/// The decode path of `steps` below the section at `key`: the leading field
/// steps join the key path, and the steps from the first list index on are
/// the suffix.
fn decode_path_below(key : KeyPath?, steps : Array[DecodeStep]) -> DecodePath {
  let names = match key {
    Some(key) => key.names.copy()
    None => []
  }
  let suffix : Array[DecodeStep] = []
  for step in steps {
    match step {
      Field(name) if suffix.is_empty() => names.push(name)
      _ => suffix.push(step)
    }
  }
  { key: if names.is_empty() { None } else { Some({ names, }) }, suffix }
}

///|
/// The JSON form of a section. A value with no JSON form fails as a decode
/// error at the section.
fn section_json(
  config : Config,
  key : KeyPath?,
  value : ConfigValue,
) -> Json raise ConfigError {
  @ion_json.to_json(value.ion) catch {
    error => {
      let path : DecodePath = { key, suffix: [] }
      raise Decode(failure={
        at: [{ path, blame: config.blame(path) }],
        detail: "the value has no JSON form: \{error.message()}",
      })
    }
  }
}

///|
fn[T : FromJson] decode(
  config : Config,
  key : KeyPath?,
  json : Json,
  blame? : (DecodePath) -> Blame,
) -> T raise ConfigError {
  let blame = blame.unwrap_or(path => config.blame(path))
  @json.from_json(json) catch {
    JsonDecodeError((pointer, detail)) => {
      let path = decode_path(key, pointer.to_string(), json)
      raise Decode(failure={ at: [{ path, blame: blame(path) }], detail })
    }
  }
}

///|
/// Decode the section at `key` merged over `default`. The default is written
/// with `ToJson`, the configured section merges over it with the core merge
/// rules, and the result decodes into a `T`: tables merge, a configured list
/// or scalar replaces the default, and an absent section keeps the default.
/// A `None` field of the default is not written, so a configured value fills
/// it. A failure in a value that the default gave has the blame `Default`. A
/// secret reference in the configured section raises `Decode` before the
/// merge. The default does not change.
///
/// `unknown` turns on the unknown-key check: with `Reject`, each configured
/// key that the `ToJson` form of the result does not hold is a failure with
/// its sources, and all of them raise one `Validation` error. The check is
/// correct only when `ToJson` writes every key that `FromJson` accepts, under
/// the same name; `RejectExcept` lists the other keys that the type accepts.
pub fn[T : FromJson + ToJson] bind_or(
  config : Config,
  key : String,
  default : T,
  unknown? : UnknownKeys = Allow,
) -> T raise ConfigError {
  let path = KeyPath::parse(key)
  // Synthetic roots keep the rule that a tree root is a struct, so a scalar or
  // list default works too.
  let default_root = fields([("value", { ion: @ion.Ion::Ion(ToJson::to_json(default)) })])
  let section = config.get(path)
  let merged = match section {
    Some(section) => {
      config.check_no_secret(Some(path), section)
      merge(default_root, fields([("value", section)]))
    }
    None => default_root
  }
  let value = merged.field("value").unwrap_or({ ion: @ion.Ion::Ion(Json::null()) })
  let json = section_json(config, Some(path), value)
  let result : T = decode(config, Some(path), json, blame=decode_path => {
    match config.blame(decode_path) {
      Unset | Table([]) => {
        let below = match decode_path.key {
          Some(failing) => failing.names[path.names.length():].to_owned()
          None => []
        }
        if default_root.at(["value", ..below]) is Some(_) {
          Default
        } else {
          Unset
        }
      }
      blame => blame
    }
  })
  if section is Some(section) && !(unknown is Allow) {
    config.check_unknown_keys(path, section, ToJson::to_json(result), unknown)
  }
  result
}

///|
/// Decode the section at `key` merged over `default`, as `bind_or` does.
pub fn[T : FromJson + ToJson] Config::bind_or(
  self : Config,
  key : String,
  default : T,
  unknown? : UnknownKeys = Allow,
) -> T raise ConfigError {
  bind_or(self, key, default, unknown~)
}

///|
/// The decode path of a JSON Pointer (RFC 6901) below the section at `key`.
/// A segment is a list index when the JSON value there is an array. The key
/// path takes the names up to the first list index; the suffix takes the
/// steps from that index on.
fn decode_path(key : KeyPath?, pointer : String, json : Json) -> DecodePath {
  let names = match key {
    Some(key) => key.names.copy()
    None => []
  }
  let suffix : Array[DecodeStep] = []
  let mut node : Json? = Some(json)
  for segment in pointer_segments(pointer) {
    let step : DecodeStep = match (node, list_index(segment)) {
      (Some(Array(items)), Some(index)) => {
        node = items.get(index)
        Index(index)
      }
      (Some(Object(fields)), _) => {
        node = fields.get(segment)
        Field(segment)
      }
      _ => {
        node = None
        Field(segment)
      }
    }
    match step {
      Field(name) if suffix.is_empty() => names.push(name)
      _ => suffix.push(step)
    }
  }
  { key: if names.is_empty() { None } else { Some({ names, }) }, suffix }
}

///|
/// The unescaped segments of a JSON Pointer: `~1` is `/` and `~0` is `~`.
fn pointer_segments(pointer : String) -> Array[String] {
  guard pointer.has_prefix("/") else { return [] }
  pointer[1:]
  .split("/")
  .map(segment => {
    segment
    .to_owned()
    .replace_all(old="~1", new="/")
    .replace_all(old="~0", new="~")
  })
  .collect()
}

///|
/// The list index that `segment` names, when it is a decimal number.
fn list_index(segment : String) -> Int? {
  guard !segment.is_empty() && segment.length() <= 9 else { return None }
  let mut index = 0
  for char in segment {
    guard char >= '0' && char <= '9' else { return None }
    index = index * 10 + (char.to_int() - '0'.to_int())
  }
  Some(index)
}

///|
/// The sources to blame for a decode path. Provenance has no list index, so
/// the lookup uses the key part. A leaf or a list gives `Set` with its origins.
/// A table gives `Table` with the distinct origins of its leaves, in merge
/// order. A key that no source sets gives `Unset`.
fn Config::blame(self : Config, path : DecodePath) -> Blame {
  guard path.key is Some(key) else { return Table(self.table_origins([])) }
  let origins = self.origins(key)
  if !origins.is_empty() {
    return Set(origins)
  }
  match self.get(key) {
    Some(value) if value.ion.kind() is Struct(_) =>
      Table(self.table_origins(key.names))
    _ => Unset
  }
}

///|
/// The distinct origins of the leaves below `names`, in merge order.
fn Config::table_origins(self : Config, names : Array[String]) -> Array[Origin] {
  let prefix : KeyPath = { names, }
  let origins : Array[Origin] = []
  for leaf in self.provenance() {
    let (path, leaf_origins) = leaf
    guard is_prefix(prefix, path) else { continue }
    for origin in leaf_origins {
      if !origins.contains(origin) {
        origins.push(origin)
      }
    }
  }
  // A report with no path can stand for origins with locations, for example
  // the variables of an environment source.
  let rank = (origin : Origin) => {
    self.reports
    .search_by(report => {
      report.kind == origin.kind &&
      report.name == origin.source &&
      report.priority == origin.priority &&
      (report.path is None || report.path == origin.location)
    })
    .unwrap_or(self.reports.length())
  }
  // Order by report position; ties keep their first-seen order.
  let ranked = origins.mapi((index, origin) => (rank(origin), index, origin))
  ranked.sort_by((a, b) => (a.0, a.1).compare((b.0, b.1)))
  ranked.map(entry => entry.2)
}
