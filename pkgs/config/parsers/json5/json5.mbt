///|
/// The largest magnitude that becomes an integer: 2^53.
let max_safe_integer : Double = 9007199254740992.0

///|
/// The JSON5 format for `.json` and `.json5` files.
pub fn format() -> @config.Format {
  {
    name: "JSON5",
    extensions: ["json", "json5"],
    parse: (text, origin) => parse(text, origin~),
  }
}

///|
/// Parse JSON or JSON5 text into a value tree. An integral number with a
/// magnitude of 2^53 or less becomes an integer; every other number becomes a
/// float. `origin` names the source in errors.
pub fn parse(
  text : String,
  origin~ : String,
) -> @config.ConfigValue raise @config.ConfigError {
  let json = @json5_lib.parse(text) catch {
    error => raise parse_error(origin, error)
  }
  @config.ConfigValue::from_ion(to_ion(json), origin~)
}

///|
/// Map a JSON value to Ion with the configuration number rule.
fn to_ion(value : Json) -> @ion.Ion {
  match value {
    Null => @ion.Ion::untyped_null()
    True => @ion.Ion::bool(true)
    False => @ion.Ion::bool(false)
    Number(number, ..) => number_ion(number)
    String(text) => @ion.Ion::string(text)
    Array(items) => @ion.Ion::list(items.map(to_ion))
    Object(fields) =>
      @ion.Ion::from_fields(
        fields.to_array().map(entry => @ion.field(entry.0, to_ion(entry.1))),
      )
  }
}

///|
/// An integral number within ±2^53 becomes an Ion integer; otherwise a float.
fn number_ion(number : Double) -> @ion.Ion {
  if number == number.trunc() &&
      !number.is_nan() &&
      number.abs() <= max_safe_integer {
    @ion.Ion::big_int(@bigint.BigInt::from_int64(number.to_int64()))
  } else {
    @ion.Ion::float(number)
  }
}

///|
fn parse_error(
  origin : String,
  error : @json5_lib.ParseError,
) -> @config.ConfigError {
  // json5 Position.column is 0-based; ConfigError columns are 1-based.
  let (line, column) = match error {
    @json5_lib.ParseError(@json5_lib.NoValidToken({ line, column, })) =>
      (Some(line), Some(column + 1))
    @json5_lib.ParseError(@json5_lib.InvalidChar({ line, column, }, _)) =>
      (Some(line), Some(column + 1))
    @json5_lib.ParseError(@json5_lib.InvalidNumber({ line, column, }, _)) =>
      (Some(line), Some(column + 1))
    @json5_lib.ParseError(@json5_lib.InvalidIdentEscape({ line, column, })) =>
      (Some(line), Some(column + 1))
    @json5_lib.ParseError(@json5_lib.InvalidEof) => (None, None)
  }
  Parse(
    format="JSON5",
    origin~,
    message=error.to_string(),
    line~,
    column~,
  )
}
