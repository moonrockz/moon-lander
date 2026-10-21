///|
/// A merged configuration. Its root is always a struct.
pub struct Config {
  priv root : ConfigValue
}

///|
/// Merge the sources in list order: a later source wins.
pub fn build(sources : Array[ConfigSource]) -> Config {
  { root: sources.fold(init=fields([]), (root, source) => merge(root, source.value)) }
}

///|
/// The merged value tree.
pub fn Config::value(self : Config) -> ConfigValue {
  self.root
}

///|
/// The value at `key`, or `None` when no value is there.
pub fn Config::get(self : Config, key : KeyPath) -> ConfigValue? {
  let mut value = self.root
  for name in key.names {
    guard value.field(name) is Some(next) else { return None }
    value = next
  }
  Some(value)
}

///|
/// The value at the key path `key` as text: a string gives its text, and any
/// other value gives compact JSON. A missing key raises `KeyNotFound`.
pub fn get_text(config : Config, key : String) -> String raise ConfigError {
  let path = KeyPath::parse(key)
  guard config.get(path) is Some(value) else { raise KeyNotFound(key=path) }
  match value.ion.kind() {
    String(text) => text
    _ => {
      let json = @ion_json.to_json(value.ion) catch {
        err => raise Render(format="JSON", key=path, reason=err.message())
      }
      json.stringify()
    }
  }
}
