///|
/// Decode the section at `key` into a `T`. `key` is the text form of a key
/// path, for example `ir` or `servers."eu.west"`. A section that no source sets
/// decodes as `null`, so an `Option` target gives `None`. A decode failure
/// raises `Decode` with the decode path, the decoder detail, and the sources to
/// blame. Binding does not change the configuration.
pub fn[T : FromJson] bind(config : Config, key : String) -> T raise ConfigError {
  let path = KeyPath::parse(key)
  match config.get(path) {
    Some(value) => decode(config, Some(path), section_json(config, Some(path), value))
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
  decode(config, None, section_json(config, None, config.root))
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
) -> T raise ConfigError {
  @json.from_json(json) catch {
    JsonDecodeError((pointer, detail)) => {
      let path = decode_path(key, pointer.to_string(), json)
      raise Decode(failure={ at: [{ path, blame: config.blame(path) }], detail })
    }
  }
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
  let rank = (origin : Origin) => {
    self.reports
    .search_by(report => {
      report.kind == origin.kind &&
      report.name == origin.source &&
      report.priority == origin.priority &&
      report.path == origin.location
    })
    .unwrap_or(self.reports.length())
  }
  // Order by report position; ties keep their first-seen order.
  let ranked = origins.mapi((index, origin) => (rank(origin), index, origin))
  ranked.sort_by((a, b) => (a.0, a.1).compare((b.0, b.1)))
  ranked.map(entry => entry.2)
}
