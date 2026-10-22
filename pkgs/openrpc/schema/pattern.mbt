///|
/// A syntax error offset refers to UTF-16 units in the decoded pattern string.
/// It is not a span in the JSON source containing that string.
pub struct PatternError {
  code : @json.Code
  message : String
  offset : Int32
} derive(Debug)

///|
pub extend PatternError with @debug.Debug::{to_repr}

///|
pub fn PatternError::code(self : PatternError) -> @json.Code {
  self.code
}

///|
pub fn PatternError::message(self : PatternError) -> String {
  self.message
}

///|
pub fn PatternError::offset(self : PatternError) -> Int32 {
  self.offset
}

///|
priv suberror PatternRead {
  PatternRead(PatternError)
} derive(Debug)

///|
priv struct PatternReader {
  source : String
  limits : @json.Limits
  named : Bool
  mut at : Int32
  mut nodes : Int32
  names : Set[String]
  references : Array[(String, Int32)]
}

///|
fn[T] PatternReader::error(
  self : PatternReader,
  message : String,
  offset~ : Int32 = self.at,
) -> T raise PatternRead {
  raise PatternRead(PatternError::{
    code: @json.InvalidSchema,
    message,
    offset,
  })
}

///|
fn PatternReader::limit(
  self : PatternReader,
  message : String,
) -> Unit raise PatternRead {
  raise PatternRead(PatternError::{
    code: @json.LimitExceeded,
    message,
    offset: self.at,
  })
}

///|
fn PatternReader::charge(self : PatternReader) -> Unit raise PatternRead {
  if self.nodes >= self.limits.max_nodes() {
    self.limit("Pattern group/reference limit exceeded")
  }
  self.nodes += 1
}

///|
fn pattern_digit(c : UInt16) -> Bool {
  c >= 48 && c <= 57
}

///|
fn pattern_letter(c : UInt16) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

///|
fn pattern_hex(c : UInt16) -> Int32? {
  if pattern_digit(c) {
    Some(c.to_int() - 48)
  } else if c >= 65 && c <= 70 {
    Some(c.to_int() - 55)
  } else if c >= 97 && c <= 102 {
    Some(c.to_int() - 87)
  } else {
    None
  }
}

///|
fn PatternReader::hex(self : PatternReader, count : Int32) -> Int32? {
  if count > self.source.length() - self.at {
    return None
  }
  let mut result = 0
  for i in 0..<count {
    guard pattern_hex(self.source.code_unit_at(self.at + i)) is Some(digit) else {
      return None
    }
    result = result * 16 + digit
  }
  self.at += count
  Some(result)
}

///|
fn unicode_range_contains(code : Int32, ranges : Array[(Int32, Int32)]) -> Bool {
  let mut low = 0
  let mut high = ranges.length()
  while low < high {
    let middle = low + (high - low) / 2
    let (first, last) = ranges[middle]
    if code < first {
      high = middle
    } else if code > last {
      low = middle + 1
    } else {
      return true
    }
  }
  false
}

///|
// ECMAScript2018 without U parses group names as BMP source characters.
fn PatternReader::group_name(self : PatternReader) -> String raise PatternRead {
  guard self.at < self.source.length() &&
    self.source.code_unit_at(self.at) == 60 else {
    self.error("Expected a group name")
  }
  self.at += 1
  let result = StringBuilder()
  let mut first = true
  while self.at < self.source.length() &&
        self.source.code_unit_at(self.at) != 62 {
    let mut code = self.source.code_unit_at(self.at).to_int()
    if code == 92 {
      self.at += 1
      guard self.at < self.source.length() &&
        self.source.code_unit_at(self.at) == 117 else {
        self.error("Group-name escape must use u and four hex digits")
      }
      self.at += 1
      code = match self.hex(4) {
        Some(c) => c
        None => self.error("Invalid group-name Unicode escape")
      }
    } else {
      self.at += 1
    }
    let valid = code == 36 ||
      code == 95 ||
      (if first {
        unicode_range_contains(code, unicode_id_start)
      } else {
        code == 0x200c ||
        code == 0x200d ||
        unicode_range_contains(code, unicode_id_continue)
      })
    if !valid {
      self.error("Invalid Unicode group-name character")
    }
    result.write_char(code.unsafe_to_char())
    first = false
  }
  if first || self.at == self.source.length() {
    self.error("Empty or unterminated group name")
  }
  self.at += 1
  result.to_string()
}

///|
// None is a class escape such as d or W. It is a legal legacy range endpoint.
fn PatternReader::escape(
  self : PatternReader,
  in_class : Bool,
) -> Int32? raise PatternRead {
  let start = self.at
  self.at += 1
  if self.at == self.source.length() {
    self.error("Trailing backslash", offset=start)
  }
  let c = self.source.code_unit_at(self.at)
  self.at += 1
  match c.to_int() {
    100 | 68 | 115 | 83 | 119 | 87 => None
    98 => Some(8)
    102 => Some(12)
    110 => Some(10)
    114 => Some(13)
    116 => Some(9)
    118 => Some(11)
    99 => {
      if self.at < self.source.length() {
        let letter = self.source.code_unit_at(self.at)
        if pattern_letter(letter) ||
          (in_class && (pattern_digit(letter) || letter == 95)) {
          self.at += 1
          return Some(letter.to_int() % 32)
        }
      }
      // AnnexB permits a literal backslash followed by an unconsumed c.
      self.at = start + 1
      Some(92)
    }
    120 =>
      match self.hex(2) {
        Some(c) => Some(c)
        None => Some(120)
      }
    117 =>
      match self.hex(4) {
        Some(c) => Some(c)
        None => Some(117)
      }
    107 => {
      if self.named {
        if in_class {
          self.error(
            "Named reference is not a character-class escape",
            offset=start,
          )
        }
        let name = self.group_name()
        self.charge()
        self.references.push((name, start))
      }
      Some(107)
    }
    _ => {
      if pattern_digit(c) {
        if !in_class {
          // In no-flags AnnexB syntax every decimal escape has either a
          // capture-reference interpretation or a legacy escape fallback.
          while self.at < self.source.length() &&
                pattern_digit(self.source.code_unit_at(self.at)) {
            self.at += 1
          }
        } else if c <= 55 {
          let mut value = c.to_int() - 48
          let count = if c <= 51 { 2 } else { 1 }
          for _ in 0..<count {
            if self.at == self.source.length() {
              break
            }
            let next = self.source.code_unit_at(self.at)
            if next < 48 || next > 55 {
              break
            }
            value = value * 8 + next.to_int() - 48
            self.at += 1
          }
          return Some(value)
        }
      }
      Some(c.to_int())
    }
  }
}

///|
fn PatternReader::class_atom(self : PatternReader) -> Int32? raise PatternRead {
  if self.at == self.source.length() {
    self.error("Unterminated character class")
  }
  if self.source.code_unit_at(self.at) == 92 {
    self.escape(true)
  } else {
    let code = self.source.code_unit_at(self.at).to_int()
    self.at += 1
    Some(code)
  }
}

///|
fn PatternReader::character_class(
  self : PatternReader,
) -> Unit raise PatternRead {
  self.at += 1
  if self.at < self.source.length() && self.source.code_unit_at(self.at) == 94 {
    self.at += 1
  }
  while self.at < self.source.length() &&
        self.source.code_unit_at(self.at) != 93 {
    let first = self.class_atom()
    if self.at < self.source.length() - 1 &&
      self.source.code_unit_at(self.at) == 45 &&
      self.source.code_unit_at(self.at + 1) != 93 {
      self.at += 1
      let last = self.class_atom()
      if first is Some(a) && last is Some(b) && a > b {
        self.error("Character range is out of order")
      }
    }
  }
  if self.at == self.source.length() {
    self.error("Unterminated character class")
  }
  self.at += 1
}

///|
fn decimal_greater(left : StringView, right : StringView) -> Bool {
  let mut a_start = 0
  let mut b_start = 0
  while a_start < left.length() && left.code_unit_at(a_start) == 48 {
    a_start += 1
  }
  while b_start < right.length() && right.code_unit_at(b_start) == 48 {
    b_start += 1
  }
  let a = left[a_start:]
  let b = right[b_start:]
  a.length() > b.length() ||
  (a.length() == b.length() && a.lexical_compare(b) > 0)
}

///|
// Recognize a full braced quantifier. Incomplete braces are legacy literals.
fn PatternReader::braced(self : PatternReader) -> Bool raise PatternRead {
  let start = self.at
  let mut end = start + 1
  let first = end
  while end < self.source.length() &&
        pattern_digit(self.source.code_unit_at(end)) {
    end += 1
  }
  if first == end {
    return false
  }
  let first_end = end
  let mut second = end
  let mut second_end = end
  if end < self.source.length() && self.source.code_unit_at(end) == 44 {
    end += 1
    second = end
    while end < self.source.length() &&
          pattern_digit(self.source.code_unit_at(end)) {
      end += 1
    }
    second_end = end
  }
  if end == self.source.length() || self.source.code_unit_at(end) != 125 {
    return false
  }
  if first_end - first > self.limits.max_number() ||
    second_end - second > self.limits.max_number() {
    self.limit("Pattern quantifier digit limit exceeded")
  }
  if second_end > second &&
    decimal_greater(
      self.source[first:first_end],
      self.source[second:second_end],
    ) {
    self.error("Quantifier bounds are out of order")
  }
  self.at = end + 1
  true
}

///|
fn read_pattern(
  source : String,
  limits : @json.Limits,
  named : Bool,
) -> Bool raise PatternRead {
  let reader = PatternReader::{
    source,
    limits,
    named,
    at: 0,
    nodes: 0,
    names: Set([]),
    references: [],
  }
  let groups : Array[Bool] = []
  let mut quantifiable = false
  while reader.at < source.length() {
    let start = reader.at
    let c = source.code_unit_at(start)
    match c.to_int() {
      40 => {
        reader.charge()
        reader.at += 1
        let mut can_repeat = true
        if reader.at < source.length() && source.code_unit_at(reader.at) == 63 {
          reader.at += 1
          if reader.at == source.length() {
            reader.error("Unterminated group prefix")
          }
          match source.code_unit_at(reader.at).to_int() {
            58 | 61 | 33 => reader.at += 1
            60 =>
              if reader.at + 1 < source.length() &&
                (
                  source.code_unit_at(reader.at + 1) == 61 ||
                  source.code_unit_at(reader.at + 1) == 33
                ) {
                reader.at += 2
                can_repeat = false
              } else {
                let name = reader.group_name()
                if reader.names.contains(name) {
                  reader.error("Duplicate capture group name", offset=start)
                }
                reader.names.add(name)
              }
            _ => reader.error("Invalid group prefix")
          }
        }
        if groups.length() >= limits.max_depth() {
          reader.limit("Pattern nesting limit exceeded")
        }
        groups.push(can_repeat)
        quantifiable = false
      }
      41 => {
        guard groups.pop() is Some(can_repeat) else {
          reader.error("Unmatched closing parenthesis")
        }
        reader.at += 1
        quantifiable = can_repeat
      }
      42 | 43 | 63 => {
        if !quantifiable {
          reader.error("Quantifier has no repeatable atom")
        }
        reader.at += 1
        if reader.at < source.length() && source.code_unit_at(reader.at) == 63 {
          reader.at += 1
        }
        quantifiable = false
      }
      123 =>
        if reader.braced() {
          if !quantifiable {
            reader.error("Quantifier has no repeatable atom", offset=start)
          }
          if reader.at < source.length() && source.code_unit_at(reader.at) == 63 {
            reader.at += 1
          }
          quantifiable = false
        } else {
          reader.at += 1
          quantifiable = true
        }
      91 => {
        reader.character_class()
        quantifiable = true
      }
      92 =>
        if start + 1 < source.length() &&
          (
            source.code_unit_at(start + 1) == 98 ||
            source.code_unit_at(start + 1) == 66
          ) {
          reader.at += 2
          quantifiable = false
        } else {
          ignore(reader.escape(false))
          quantifiable = true
        }
      94 | 36 | 124 => {
        reader.at += 1
        quantifiable = false
      }
      _ => {
        reader.at += 1
        quantifiable = true
      }
    }
  }
  if !groups.is_empty() {
    reader.error("Unterminated parenthesized group")
  }
  for (name, offset) in reader.references {
    if !reader.names.contains(name) {
      reader.error("Named reference has no matching capture", offset~)
    }
  }
  !reader.names.is_empty()
}

///|
/// Check ECMA-262 2018 pattern syntax with no flags and Annex B extensions.
/// This performs no matching, fetching, compilation or instance evaluation.
pub fn check_pattern(
  source : String,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Unit, PatternError] {
  if source.length() > limits.max_source() {
    return Err(PatternError::{
      code: @json.LimitExceeded,
      message: "Pattern source limit exceeded",
      offset: 0,
    })
  }
  try {
    let named = read_pattern(source, limits, false)
    if named {
      ignore(read_pattern(source, limits, true))
    }
    Ok(())
  } catch {
    PatternRead(error) => Err(error)
  }
}
