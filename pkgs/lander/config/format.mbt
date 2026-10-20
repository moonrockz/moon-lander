///|
/// A configuration file format. `parse` takes the text and the origin, for
/// example a file path, and gives a value tree with a struct root.
pub(all) struct Format {
  name : String
  extensions : Array[String]
  parse : (String, String) -> ConfigValue raise ConfigError
}
