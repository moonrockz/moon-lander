///|
/// The TOML format for `.toml` files.
pub fn format() -> @config.Format {
  { name: "TOML", extensions: ["toml"], parse: (text, origin) => parse(text, origin~) }
}

///|
/// Parse TOML text into a value tree. A string gives a string, an integer an
/// integer, a float a float, a Boolean a Boolean, an array a list, and a table
/// a struct with the keys in source order. `origin` names the source in errors.
pub fn parse(
  text : String,
  origin~ : String,
) -> @config.ConfigValue raise @config.ConfigError {
  let document = @toml_lib.parse(text) catch {
    error => raise parse_error(origin, error.to_string())
  }
  @config.ConfigValue::from_ion(to_ion(document, origin))
}

///|
fn to_ion(
  value : @toml_lib.TomlValue,
  origin : String,
) -> @ion.Ion raise @config.ConfigError {
  match value {
    TomlString(text) => @ion.Ion::string(text)
    TomlInteger(number) => @ion.Ion::big_int(@bigint.BigInt::from_int64(number))
    TomlFloat(number) => @ion.Ion::float(number)
    TomlBoolean(flag) => @ion.Ion::bool(flag)
    TomlArray(items) => @ion.Ion::list(items.map(item => to_ion(item, origin)))
    TomlTable(entries) =>
      @ion.Ion::from_fields(
        entries
        .to_array()
        .map(entry => @ion.field(entry.0, to_ion(entry.1, origin))),
      )
    TomlDateTime(_) =>
      raise parse_error(origin, "TOML date and time values are not supported yet")
  }
}

///|
fn parse_error(origin : String, message : String) -> @config.ConfigError {
  Parse(format="TOML", origin~, message~, line=None, column=None)
}
