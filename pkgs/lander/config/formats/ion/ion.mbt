///|
/// The Ion text format for `.ion` files.
pub fn format() -> @config.Format {
  { name: "Ion", extensions: ["ion"], parse: (text, origin) => parse(text, origin~) }
}

///|
/// Parse Ion text into a value tree. The text must hold exactly one top-level
/// struct. Decimals, timestamps, symbols, annotations, and integers of any
/// size stay exact. A repeated field name raises `DuplicateKey`. `origin`
/// names the source in errors.
pub fn parse(
  text : String,
  origin~ : String,
) -> @config.ConfigValue raise @config.ConfigError {
  let values = @text.read_ion_datagram(text[:]) catch {
    error => raise parse_error(origin, error)
  }
  guard values.length() == 1 else {
    raise InvalidRoot(origin~, found="datagram")
  }
  @config.ConfigValue::from_ion(values[0], origin~)
}

///|
fn parse_error(
  origin : String,
  error : @ion_lib.IonError,
) -> @config.ConfigError {
  Parse(
    format="Ion",
    origin~,
    message=error.message(),
    line=None,
    column=None,
  )
}
