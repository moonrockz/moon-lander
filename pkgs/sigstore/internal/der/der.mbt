///|
/// Bytes that are not strict DER.
pub(all) suberror DerError {
  /// The bytes break the rule that the text names.
  Malformed(String)
} derive(Debug)

///|
pub extend DerError with @debug.Debug::{to_repr}

///|
pub fn DerError::message(self : DerError) -> String {
  let Malformed(rule) = self
  "malformed DER: \{rule}"
}

///|
pub const BOOLEAN : Int = 0x01

///|
pub const INTEGER : Int = 0x02

///|
pub const BIT_STRING : Int = 0x03

///|
pub const OCTET_STRING : Int = 0x04

///|
pub const NULL : Int = 0x05

///|
pub const OID : Int = 0x06

///|
pub const UTF8_STRING : Int = 0x0c

///|
pub const PRINTABLE_STRING : Int = 0x13

///|
pub const IA5_STRING : Int = 0x16

///|
pub const UTC_TIME : Int = 0x17

///|
pub const GENERALIZED_TIME : Int = 0x18

///|
pub const SEQUENCE : Int = 0x30

///|
pub const SET : Int = 0x31

///|
/// The identifier of a context-specific constructed tag `[n]`.
pub fn context(n : Int) -> Int {
  0xa0 | n
}

///|
/// The identifier of a context-specific primitive tag `[n]`.
pub fn context_primitive(n : Int) -> Int {
  0x80 | n
}

///|
/// One DER element: its identifier byte, its content and all of its bytes.
pub struct Element {
  tag : Int
  content : BytesView
  raw : BytesView
}

///|
/// A cursor over consecutive DER elements.
pub struct Reader {
  priv bytes : BytesView
  priv mut at : Int
}

///|
pub fn Reader::new(bytes : BytesView) -> Reader {
  { bytes, at: 0 }
}

///|
pub fn Reader::is_empty(self : Reader) -> Bool {
  self.at >= self.bytes.length()
}

///|
/// The identifier byte of the next element, without reading it.
pub fn Reader::peek_tag(self : Reader) -> Int? {
  if self.is_empty() {
    None
  } else {
    Some(self.bytes[self.at].to_int())
  }
}

///|
/// Read the next element. Only the single-byte identifier form and minimal
/// definite lengths are DER.
pub fn Reader::next(self : Reader) -> Element raise DerError {
  let bytes = self.bytes
  let start = self.at
  guard start + 2 <= bytes.length() else { raise Malformed("truncated header") }
  let tag = bytes[start].to_int()
  guard (tag & 0x1f) != 0x1f else { raise Malformed("multi-byte tag") }
  let first = bytes[start + 1].to_int()
  let mut length = 0
  let mut header = 2
  if first < 0x80 {
    length = first
  } else {
    let count = first & 0x7f
    guard count >= 1 && count <= 3 else { raise Malformed("length form") }
    guard start + 2 + count <= bytes.length() else {
      raise Malformed("truncated length")
    }
    guard bytes[start + 2] != b'\x00' else { raise Malformed("length has a leading zero") }
    for i in 0..<count {
      length = (length << 8) | bytes[start + 2 + i].to_int()
    }
    guard length >= 0x80 else { raise Malformed("length is not minimal") }
    header = 2 + count
  }
  let end = start + header + length
  guard end <= bytes.length() else { raise Malformed("content is truncated") }
  self.at = end
  { tag, content: bytes[start + header:end], raw: bytes[start:end] }
}

///|
/// Read the next element and require the identifier `tag`.
pub fn Reader::expect(self : Reader, tag : Int) -> Element raise DerError {
  let element = self.next()
  guard element.tag == tag else {
    raise Malformed("expected tag \{tag}, found \{element.tag}")
  }
  element
}

///|
/// Read the next element when it has the identifier `tag`.
pub fn Reader::optional(self : Reader, tag : Int) -> Element? raise DerError {
  if self.peek_tag() == Some(tag) {
    Some(self.next())
  } else {
    None
  }
}

///|
/// Require that no bytes remain.
pub fn Reader::finish(self : Reader) -> Unit raise DerError {
  guard self.is_empty() else { raise Malformed("trailing bytes") }
}

///|
/// Read exactly one element that fills `bytes`.
pub fn parse(bytes : BytesView) -> Element raise DerError {
  let reader = Reader::new(bytes)
  let element = reader.next()
  reader.finish()
  element
}

///|
/// Read exactly one element with the identifier `tag` that fills `bytes`.
pub fn parse_tag(bytes : BytesView, tag : Int) -> Element raise DerError {
  let element = parse(bytes)
  guard element.tag == tag else {
    raise Malformed("expected tag \{tag}, found \{element.tag}")
  }
  element
}

///|
/// A reader over the children of a constructed element.
pub fn Element::children(self : Element) -> Reader raise DerError {
  guard (self.tag & 0x20) != 0 else { raise Malformed("element is not constructed") }
  Reader::new(self.content)
}

///|
/// The magnitude bytes of a non-negative INTEGER, without a sign byte.
pub fn Element::unsigned(self : Element) -> BytesView raise DerError {
  guard self.tag == INTEGER else { raise Malformed("expected INTEGER") }
  let content = self.content
  guard content.length() > 0 else { raise Malformed("empty INTEGER") }
  guard content[0].to_int() < 0x80 else { raise Malformed("negative INTEGER") }
  if content.length() > 1 && content[0] == b'\x00' {
    guard content[1].to_int() >= 0x80 else { raise Malformed("INTEGER is not minimal") }
    content[1:]
  } else {
    content
  }
}

///|
/// A small non-negative INTEGER.
pub fn Element::small_int(self : Element) -> Int raise DerError {
  let magnitude = self.unsigned()
  guard magnitude.length() <= 3 else { raise Malformed("INTEGER is too large") }
  let mut value = 0
  for byte in magnitude {
    value = (value << 8) | byte.to_int()
  }
  value
}

///|
/// A BOOLEAN; DER allows only 0x00 and 0xff.
pub fn Element::boolean(self : Element) -> Bool raise DerError {
  guard self.tag == BOOLEAN && self.content.length() == 1 else {
    raise Malformed("expected BOOLEAN")
  }
  match self.content[0] {
    b'\x00' => false
    b'\xff' => true
    _ => raise Malformed("BOOLEAN is not 0x00 or 0xff")
  }
}

///|
/// The bytes of a BIT STRING with no unused bits.
pub fn Element::bit_string_bytes(self : Element) -> BytesView raise DerError {
  guard self.tag == BIT_STRING && self.content.length() >= 1 else {
    raise Malformed("expected BIT STRING")
  }
  guard self.content[0] == b'\x00' else { raise Malformed("BIT STRING has unused bits") }
  self.content[1:]
}

///|
/// The bits of a BIT STRING as an integer with bit 0 first, as X.509 key usage
/// names them. At most 16 bits.
pub fn Element::named_bits(self : Element) -> Int raise DerError {
  guard self.tag == BIT_STRING && self.content.length() >= 1 else {
    raise Malformed("expected BIT STRING")
  }
  let unused = self.content[0].to_int()
  let data = self.content[1:]
  guard unused <= 7 && data.length() <= 2 else { raise Malformed("BIT STRING is too long") }
  guard data.length() > 0 || unused == 0 else { raise Malformed("BIT STRING unused bits") }
  // DER sets the unused bits to zero (X.690, section 11.2.1).
  guard data.length() == 0 ||
    (data[data.length() - 1].to_int() & ((1 << unused) - 1)) == 0 else {
    raise Malformed("BIT STRING unused bits are not zero")
  }
  let mut bits = 0
  for i in 0..<data.length() {
    let byte = data[i].to_int()
    for j in 0..<8 {
      if (byte & (0x80 >> j)) != 0 {
        bits = bits | (1 << (i * 8 + j))
      }
    }
  }
  bits
}

///|
/// The dotted text of an OBJECT IDENTIFIER.
pub fn Element::oid(self : Element) -> String raise DerError {
  guard self.tag == OID && self.content.length() > 0 else { raise Malformed("expected OID") }
  let parts : Array[UInt64] = []
  let mut value : UInt64 = 0
  let mut fresh = true
  for byte in self.content {
    let b = byte.to_int()
    guard !(fresh && b == 0x80) else { raise Malformed("OID arc is not minimal") }
    guard value < (1UL << 56) else { raise Malformed("OID arc is too large") }
    value = (value << 7) | (b & 0x7f).to_uint64()
    if (b & 0x80) == 0 {
      parts.push(value)
      value = 0
      fresh = true
    } else {
      fresh = false
    }
  }
  guard fresh else { raise Malformed("OID is truncated") }
  let first = parts[0]
  let out = StringBuilder()
  if first < 40 {
    out.write_string("0.\{first}")
  } else if first < 80 {
    out.write_string("1.\{first - 40}")
  } else {
    out.write_string("2.\{first - 80}")
  }
  for i in 1..<parts.length() {
    out.write_string(".\{parts[i]}")
  }
  out.to_string()
}

///|
/// The text of a UTF8String, PrintableString or IA5String.
pub fn Element::text(self : Element) -> String raise DerError {
  guard self.tag == UTF8_STRING ||
    self.tag == PRINTABLE_STRING ||
    self.tag == IA5_STRING else {
    raise Malformed("expected a string")
  }
  @utf8.decode(self.content) catch {
    _ => raise Malformed("string is not UTF-8")
  }
}

///|
/// The time of a UTCTime or GeneralizedTime as seconds since 1970, UTC. DER
/// requires the `Z` form with seconds and no fraction.
pub fn Element::time(self : Element) -> Int64 raise DerError {
  let text = @utf8.decode(self.content) catch {
    _ => raise Malformed("time is not ASCII")
  }
  let (year, rest) = match self.tag {
    UTC_TIME => {
      guard text.length() == 13 else { raise Malformed("UTCTime form") }
      let yy = digits(text, 0, 2)
      (if yy < 50 { 2000 + yy } else { 1900 + yy }, 2)
    }
    GENERALIZED_TIME => {
      guard text.length() == 15 else { raise Malformed("GeneralizedTime form") }
      (digits(text, 0, 4), 4)
    }
    _ => raise Malformed("expected a time")
  }
  guard text[text.length() - 1] == 'Z'.to_int().to_uint16() else { raise Malformed("time is not UTC") }
  let month = digits(text, rest, 2)
  let day = digits(text, rest + 2, 2)
  let hour = digits(text, rest + 4, 2)
  let minute = digits(text, rest + 6, 2)
  let second = digits(text, rest + 8, 2)
  guard month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= days_in_month(year, month) &&
    hour <= 23 &&
    minute <= 59 &&
    second <= 59 else {
    raise Malformed("time is out of range")
  }
  unix_seconds(year, month, day, hour, minute, second)
}

///|
fn digits(text : String, start : Int, count : Int) -> Int raise DerError {
  let mut value = 0
  for i in start..<(start + count) {
    let code = text[i].to_int()
    guard code >= '0'.to_int() && code <= '9'.to_int() else {
      raise Malformed("time has a non-digit")
    }
    value = value * 10 + (code - '0'.to_int())
  }
  value
}

///|
fn is_leap(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// The number of days in a month of a year.
pub fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    2 => if is_leap(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
/// Seconds since 1970-01-01T00:00:00Z for a valid civil date and time.
pub fn unix_seconds(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
) -> Int64 {
  // Days from civil, H. Hinnant.
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (month + 9) % 12
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era.to_int64() * 146097L + doe.to_int64() - 719468L
  days * 86400L +
  hour.to_int64() * 3600L +
  minute.to_int64() * 60L +
  second.to_int64()
}

///|
/// The DER bytes of an element with the identifier `tag` and `content`.
pub fn encode(tag : Int, content : BytesView) -> Bytes {
  let out : Array[Byte] = [tag.to_byte()]
  let length = content.length()
  if length < 0x80 {
    out.push(length.to_byte())
  } else if length < 0x100 {
    out.push(b'\x81')
    out.push(length.to_byte())
  } else if length < 0x10000 {
    out.push(b'\x82')
    out.push((length >> 8).to_byte())
    out.push((length & 0xff).to_byte())
  } else {
    out.push(b'\x83')
    out.push((length >> 16).to_byte())
    out.push(((length >> 8) & 0xff).to_byte())
    out.push((length & 0xff).to_byte())
  }
  for byte in content {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// The time of a GeneralizedTime with an optional fraction of a second, as
/// seconds since 1970 and nanoseconds. DER requires the `Z` form and a fraction
/// with no trailing zero (X.690, section 11.7), of at most nine digits here.
pub fn Element::generalized_time(self : Element) -> (Int64, Int) raise DerError {
  guard self.tag == GENERALIZED_TIME else { raise Malformed("expected GeneralizedTime") }
  let text = @utf8.decode(self.content) catch {
    _ => raise Malformed("time is not ASCII")
  }
  guard text.length() >= 15 && text[text.length() - 1] == 'Z'.to_int().to_uint16() else {
    raise Malformed("GeneralizedTime form")
  }
  let whole = text[:14].to_owned() + "Z"
  let mut nanos = 0
  if text.length() > 15 {
    guard text[14] == '.'.to_int().to_uint16() else { raise Malformed("GeneralizedTime form") }
    let fraction = text[15:text.length() - 1].to_owned()
    guard fraction.length() >= 1 && fraction.length() <= 9 else {
      raise Malformed("GeneralizedTime fraction length")
    }
    guard !fraction.has_suffix("0") else {
      raise Malformed("GeneralizedTime fraction has a trailing zero")
    }
    for char in fraction {
      guard char >= '0' && char <= '9' else { raise Malformed("time has a non-digit") }
      nanos = nanos * 10 + (char.to_int() - '0'.to_int())
    }
    for _ in fraction.length()..<9 {
      nanos = nanos * 10
    }
  }
  let seconds = { tag: GENERALIZED_TIME, content: @utf8.encode(whole)[:], raw: self.raw }.time()
  (seconds, nanos)
}
