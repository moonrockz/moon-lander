///|
/// A text that is not valid base64 or hex.
pub suberror EncodingError {
  /// The text is not base64 in the standard or the URL-safe alphabet.
  BadBase64(String)
  /// The text is not an even number of hex digits.
  BadHex(String)
} derive(Debug)

///|
pub extend EncodingError with @debug.Debug::{to_repr}

///|
fn base64_value(char : Char, url : Bool) -> Int {
  match char {
    'A'..='Z' => char.to_int() - 'A'.to_int()
    'a'..='z' => char.to_int() - 'a'.to_int() + 26
    '0'..='9' => char.to_int() - '0'.to_int() + 52
    '+' if !url => 62
    '/' if !url => 63
    '-' if url => 62
    '_' if url => 63
    _ => -1
  }
}

///|
/// Decode base64 as protobuf JSON reads bytes: the URL-safe alphabet when the
/// text holds `-` or `_`, else the standard alphabet, with optional padding.
/// Line breaks are ignored, as Go's decoder does.
pub fn decode_base64(text : StringView) -> Bytes raise EncodingError {
  let url = text.contains_char('-') || text.contains_char('_')
  let values : Array[Int] = []
  let mut padding = 0
  for char in text {
    if char == '\r' || char == '\n' {
      continue
    }
    if char == '=' {
      padding += 1
      continue
    }
    guard padding == 0 else { raise BadBase64("data after padding") }
    let value = base64_value(char, url)
    guard value >= 0 else {
      raise BadBase64("the character \{char.to_string().escape()} is not allowed")
    }
    values.push(value)
  }
  let rest = values.length() % 4
  guard rest != 1 else { raise BadBase64("the length is not valid") }
  if padding > 0 {
    guard (values.length() + padding) % 4 == 0 && padding <= 2 else {
      raise BadBase64("the padding is not valid")
    }
  }
  let out = FixedArray::make(values.length() / 4 * 3 + (if rest == 0 { 0 } else { rest - 1 }), b'\x00')
  let mut at = 0
  let mut i = 0
  while i + 4 <= values.length() {
    let n = (values[i] << 18) | (values[i + 1] << 12) | (values[i + 2] << 6) | values[i + 3]
    out[at] = (n >> 16).to_byte()
    out[at + 1] = ((n >> 8) & 0xff).to_byte()
    out[at + 2] = (n & 0xff).to_byte()
    at += 3
    i += 4
  }
  if rest == 2 {
    let n = (values[i] << 18) | (values[i + 1] << 12)
    out[at] = (n >> 16).to_byte()
  } else if rest == 3 {
    let n = (values[i] << 18) | (values[i + 1] << 12) | (values[i + 2] << 6)
    out[at] = (n >> 16).to_byte()
    out[at + 1] = ((n >> 8) & 0xff).to_byte()
  }
  Bytes::from_array(out)
}

///|
let base64_alphabet : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// Encode bytes as standard base64 with padding.
pub fn encode_base64(bytes : BytesView) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < bytes.length() {
    let b0 = bytes[i].to_int()
    let b1 = if i + 1 < bytes.length() { bytes[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < bytes.length() { bytes[i + 2].to_int() } else { 0 }
    let n = (b0 << 16) | (b1 << 8) | b2
    out.write_char(base64_alphabet[(n >> 18) & 63].unsafe_to_char())
    out.write_char(base64_alphabet[(n >> 12) & 63].unsafe_to_char())
    out.write_char(
      if i + 1 < bytes.length() {
        base64_alphabet[(n >> 6) & 63].unsafe_to_char()
      } else {
        '='
      },
    )
    out.write_char(
      if i + 2 < bytes.length() {
        base64_alphabet[n & 63].unsafe_to_char()
      } else {
        '='
      },
    )
    i += 3
  }
  out.to_string()
}

///|
fn hex_value(char : Char) -> Int {
  match char {
    '0'..='9' => char.to_int() - '0'.to_int()
    'a'..='f' => char.to_int() - 'a'.to_int() + 10
    'A'..='F' => char.to_int() - 'A'.to_int() + 10
    _ => -1
  }
}

///|
/// Decode hex digits in either letter case.
pub fn decode_hex(text : StringView) -> Bytes raise EncodingError {
  guard text.length() % 2 == 0 else { raise BadHex("odd number of digits") }
  let out = FixedArray::make(text.length() / 2, b'\x00')
  for i in 0..<out.length() {
    let high = hex_value(text[2 * i].unsafe_to_char())
    let low = hex_value(text[2 * i + 1].unsafe_to_char())
    guard high >= 0 && low >= 0 else { raise BadHex("a character is not a hex digit") }
    out[i] = ((high << 4) | low).to_byte()
  }
  Bytes::from_array(out)
}

///|
/// Encode bytes as lowercase hex.
pub fn encode_hex(bytes : BytesView) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for byte in bytes {
    out.write_char(digits[byte.to_int() >> 4].unsafe_to_char())
    out.write_char(digits[byte.to_int() & 15].unsafe_to_char())
  }
  out.to_string()
}

///|
/// The bytes of an ASCII or UTF-8 text.
pub fn utf8(text : StringView) -> Bytes {
  @utf8.encode(text)
}
