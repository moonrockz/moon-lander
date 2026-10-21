///|
/// The TOML format for `.toml` files.
pub fn format() -> @config.Format {
  { name: "TOML", extensions: ["toml"], parse: (text, origin) => parse(text, origin~) }
}

///|
/// Parse TOML text into a value tree. A string gives a string, an integer an
/// integer, a float a float, a Boolean a Boolean, an array a list, and a table
/// a struct with the keys in source order. Date-times and dates give timestamps,
/// with an unknown offset for local date-times and day precision for dates.
/// Local times give strings annotated with `toml_local_time`.
/// `origin` names the source in errors.
pub fn parse(
  text : String,
  origin~ : String,
) -> @config.ConfigValue raise @config.ConfigError {
  let document = @toml_lib.parse(text) catch {
    error => raise parse_error(origin, error.to_string())
  }
  @config.ConfigValue::from_ion(to_ion(document, origin), origin~)
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
    TomlDateTime(_) => {
      let (kind, spelling) = value.datetime_info().unwrap()
      if kind == "LocalTime" {
        @ion.Ion::string(spelling).with_annotation(@ion.symbol("toml_local_time"))
      } else {
        let text = spelling.replace_all(old=" ", new="T")
          .replace_all(old="t", new="T").replace_all(old="z", new="Z")
        let text = if kind == "LocalDateTime" { text + "-00:00" } else { text }
        let timestamp = @ion.Timestamp::parse(text[:]) catch {
          error => raise parse_error(origin, error.message())
        }
        @ion.Ion::timestamp(timestamp)
      }
    }
  }
}

///|
fn parse_error(origin : String, message : String) -> @config.ConfigError {
  Parse(format="TOML", origin~, message~, line=None, column=None)
}
