///|
/// An immutable configuration source: a display name and the value tree that
/// it gives.
pub struct ConfigSource {
  name : String
  value : ConfigValue
}

///|
/// An in-memory source from a value tree. The root must be a struct.
pub fn in_memory(
  value : ConfigValue,
  name? : String = "in-memory",
) -> ConfigSource raise ConfigError {
  value.check_root(name)
  { name, value }
}

///|
/// An in-memory source from flat key-path pairs, for example
/// `("ir.layout", @config.string("tree"))`. Pairs apply in list order with the
/// merge rules, so a later pair wins. Pair values keep their type.
pub fn in_memory_pairs(
  pairs : Array[(String, ConfigValue)],
  name? : String = "in-memory",
) -> ConfigSource raise ConfigError {
  let mut value = fields([])
  for pair in pairs {
    let (text, leaf) = pair
    value = merge(value, nest(KeyPath::parse(text), leaf))
  }
  { name, value }
}

///|
/// A tree that holds `leaf` at `key`.
fn nest(key : KeyPath, leaf : ConfigValue) -> ConfigValue {
  key.names.rev_fold(init=leaf, (value, name) => fields([(name, value)]))
}
