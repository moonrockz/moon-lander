///|
/// The version of the JSON Lines schema of `format_json_line`.
const SCHEMA_VERSION : Int = 1

///|
/// True when `repr` has the complete JSON number grammar:
/// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`. A number with other
/// text, for example `1e`, `+1`, `01` or `--2`, is written from its value, so a
/// property cannot break the line.
fn is_number_text(repr : String) -> Bool {
  let chars = repr.to_array()
  let length = chars.length()
  let is_digit = (char : Char) => char >= '0' && char <= '9'
  let mut at = 0
  // Skip the digits from `at`, and give `true` when there was at least one.
  let digits = () => {
    let start = at
    while at < length && is_digit(chars[at]) {
      at += 1
    }
    at > start
  }
  if at < length && chars[at] == '-' {
    at += 1
  }
  guard at < length else { return false }
  if chars[at] == '0' {
    at += 1
  } else if !(chars[at] >= '1' && chars[at] <= '9' && digits()) {
    return false
  }
  if at < length && chars[at] == '.' {
    at += 1
    guard digits() else { return false }
  }
  if at < length && (chars[at] == 'e' || chars[at] == 'E') {
    at += 1
    if at < length && (chars[at] == '+' || chars[at] == '-') {
      at += 1
    }
    guard digits() else { return false }
  }
  at == length
}

///|
/// Write `text` as a JSON string. Each control character, including ESC, CR and
/// LF, becomes a JSON escape.
fn write_json_string(out : StringBuilder, text : String) -> Unit {
  out.write_string(Json::string(text).stringify())
}

///|
/// Write `value` as compact JSON. A number that is not finite and has no number
/// text is `null`, because JSON has no such numbers.
fn write_json(out : StringBuilder, value : Json) -> Unit {
  match value {
    Number(number, repr~) =>
      match repr {
        Some(text) if is_number_text(text) => out.write_string(text)
        _ =>
          if number.is_nan() || number.is_inf() {
            out.write_string("null")
          } else {
            out.write_string(Json::number(number).stringify())
          }
      }
    Array(items) => {
      out.write_char('[')
      for index, item in items {
        if index > 0 {
          out.write_char(',')
        }
        write_json(out, item)
      }
      out.write_char(']')
    }
    Object(fields) => {
      out.write_char('{')
      let mut first = true
      for name, field in fields {
        if !first {
          out.write_char(',')
        }
        first = false
        write_json_string(out, name)
        out.write_char(':')
        write_json(out, field)
      }
      out.write_char('}')
    }
    _ => out.write_string(value.stringify())
  }
}

///|
/// Write `text` as a JSON string, or `null` for `None`.
fn write_optional(out : StringBuilder, text : String?) -> Unit {
  match text {
    Some(text) => write_json_string(out, text)
    None => out.write_string("null")
  }
}

///|
/// Render `record` as one JSON Lines record of schema version 1: one JSON object
/// on one physical line, with a final LF, no byte order mark and no ANSI codes.
/// The keys are in this order:
///
/// | Key | Value |
/// | --- | --- |
/// | `schemaVersion` | The number `1` |
/// | `timestamp` | The UTC time, for example `"2026-10-27T14:23:07.024Z"` |
/// | `level` | The level name, for example `"Information"` |
/// | `category` | The category, or `null` |
/// | `messageTemplate` | The template as the caller wrote it |
/// | `message` | The message text |
/// | `properties` | An array of `{"name": ..., "value": ...}` objects in hole order, with each repeated name and the original JSON value |
/// | `error` | The `Show` text of the error, or `null` |
///
/// Control characters in strings are JSON escapes, for example `\n` and
/// `\u001b`. A number that is not finite becomes `null`.
pub fn format_json_line(record : LogRecord) -> String {
  let out = StringBuilder()
  out.write_string("{\"schemaVersion\":\{SCHEMA_VERSION},\"timestamp\":")
  write_json_string(out, record.timestamp.to_iso8601())
  out.write_string(",\"level\":")
  write_json_string(out, record.level.to_string())
  out.write_string(",\"category\":")
  write_optional(out, record.category)
  out.write_string(",\"messageTemplate\":")
  write_json_string(out, record.template)
  out.write_string(",\"message\":")
  write_json_string(out, record.message)
  out.write_string(",\"properties\":[")
  for index, entry in record.properties {
    if index > 0 {
      out.write_char(',')
    }
    out.write_string("{\"name\":")
    write_json_string(out, entry.0)
    out.write_string(",\"value\":")
    write_json(out, entry.1)
    out.write_char('}')
  }
  out.write_string("],\"error\":")
  write_optional(out, record.error_text)
  out.write_string("}\n")
  out.to_string()
}

///|
/// The number of bytes of `text` in UTF-8. A sink uses it to count the bytes of
/// a rendered record. A lone surrogate counts as 3 bytes, the size of the
/// replacement character that an encoder writes for it.
pub fn utf8_length(text : String) -> Int64 {
  let mut bytes = 0L
  for char in text {
    let code = char.to_int()
    bytes += if code < 0x80 {
      1L
    } else if code < 0x800 {
      2L
    } else if code < 0x10000 {
      3L
    } else {
      4L
    }
  }
  bytes
}
