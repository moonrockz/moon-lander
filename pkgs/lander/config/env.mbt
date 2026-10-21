///|
/// An environment variable source. A variable counts when its name, in upper
/// case, starts with `prefix` and `_` and is not in `reserved` (compared in
/// upper case). After the prefix, leading `_` characters go, `__` separates
/// names, and each name is written in lower case: `ACME_SERVER__PORT` sets
/// `server.port`. An empty name raises `InvalidEnvKey`.
///
/// `Discover` reads the variable set of the builder, and reports `NotFound`
/// when the builder holds none. `Explicit(vars)` reads only `vars`. `Skip`
/// loads nothing. Each value gets a type: `true` or `false` in any case is a
/// Boolean, an optional sign and digits that fit `Int64` are an integer, JSON
/// text that starts with `[` or `{` is a list or a struct, and other text is a
/// string. The origin of each value names its variable.
pub fn ConfigSource::env(
  prefix~ : String,
  reserved? : Array[String] = [],
  selection? : SourceSelection[Map[String, String]] = Discover,
  name? : String = "environment",
  priority? : Int,
) -> ConfigSource {
  let selection = match selection {
    Explicit(vars) => SourceSelection::Explicit(vars.copy())
    other => other
  }
  {
    kind: Environment,
    name,
    priority,
    input: Env(selection, prefix, reserved.copy()),
    excluded: [],
  }
}

///|
/// Add an environment variable source, as `ConfigSource::env` gives it.
pub fn env(
  builder : ConfigBuilder,
  prefix~ : String,
  reserved? : Array[String] = [],
  selection? : SourceSelection[Map[String, String]] = Discover,
) -> ConfigBuilder {
  add(builder, ConfigSource::env(prefix~, reserved~, selection~))
}

///|
/// An overrides source from key-path pairs, for example command-line values.
/// It has the kind `Overrides` and the default priority 700.
pub fn ConfigSource::overrides(
  pairs : Array[(String, ConfigValue)],
  name? : String = "overrides",
  priority? : Int,
) -> ConfigSource raise ConfigError {
  { ..in_memory_pairs(pairs, name~, priority?), kind: Overrides }
}

///|
/// An overrides source from a value tree. The root must be a struct.
pub fn ConfigSource::overrides_value(
  value : ConfigValue,
  name? : String = "overrides",
  priority? : Int,
) -> ConfigSource raise ConfigError {
  { ..in_memory(value, name~, priority?), kind: Overrides }
}

///|
/// Add an overrides source from key-path pairs.
pub fn overrides(
  builder : ConfigBuilder,
  pairs : Array[(String, ConfigValue)],
) -> ConfigBuilder raise ConfigError {
  add(builder, ConfigSource::overrides(pairs))
}

///|
/// One tree for each matching variable, with the variable name. Deeper keys
/// come first, then keys and variable names in order, so a shorter path merges
/// last and wins, whatever the order of `vars`.
fn env_pieces(
  vars : Map[String, String],
  prefix : String,
  reserved : Array[String],
) -> Array[(ConfigValue, String?)] raise ConfigError {
  let start = prefix.to_upper() + "_"
  let reserved = reserved.map(name => name.to_upper())
  let keys : Array[(Array[String], String, String)] = []
  for variable, text in vars {
    let upper = variable.to_upper()
    guard upper.has_prefix(start) && !reserved.contains(upper) else { continue }
    let mut rest = variable[start.length():].to_owned()
    while rest.has_prefix("_") {
      rest = rest[1:].to_owned()
    }
    let names = rest.split("__").map(name => name.to_owned().to_lower()).collect()
    if names.iter().any(name => name.is_empty()) {
      raise InvalidEnvKey(variable~)
    }
    keys.push((names, variable, text))
  }
  keys.sort_by((a, b) => {
    let by_depth = b.0.length().compare(a.0.length())
    if by_depth != 0 {
      return by_depth
    }
    let by_key = a.0.join(".").compare(b.0.join("."))
    if by_key != 0 {
      return by_key
    }
    a.1.compare(b.1)
  })
  keys.map(key => (nest({ names: key.0 }, env_value(key.2)), Some(key.1)))
}

///|
/// The typed value of an environment variable.
fn env_value(text : String) -> ConfigValue {
  match text.to_lower() {
    "true" => return bool(true)
    "false" => return bool(false)
    _ => ()
  }
  if parse_int64(text) is Some(number) {
    return int(number)
  }
  if text.has_prefix("[") || text.has_prefix("{") {
    let json = @json.parse(text) catch { _ => return string(text) }
    if json is (Array(_) | Object(_)) {
      return { ion: @ion.Ion::Ion(json) }
    }
  }
  string(text)
}

///|
/// The `Int64` that `text` names: an optional sign and decimal digits. Leading
/// zeros are allowed. Text out of range gives `None`.
fn parse_int64(text : String) -> Int64? {
  let (negative, digits) = if text.has_prefix("-") {
    (true, text[1:].to_owned())
  } else if text.has_prefix("+") {
    (false, text[1:].to_owned())
  } else {
    (false, text)
  }
  guard !digits.is_empty() else { return None }
  // Work in negative numbers, which reach Int64 minimum.
  let mut value = 0L
  for char in digits {
    guard char >= '0' && char <= '9' else { return None }
    let digit = (char.to_int() - '0'.to_int()).to_int64()
    guard value >= (@int64.MIN_VALUE + digit) / 10L else { return None }
    value = value * 10L - digit
  }
  if negative {
    Some(value)
  } else if value == @int64.MIN_VALUE {
    None
  } else {
    Some(-value)
  }
}
