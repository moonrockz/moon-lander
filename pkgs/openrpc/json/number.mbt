///|
fn digit(c : UInt16) -> Bool {
  c >= 48 && c <= 57
}

///|
pub fn Number::parse(token : String) -> Result[Number, Diagnostic] {
  let chars = token.code_units()
  let mut i = 0
  if i < chars.length() && chars[i] == 45 {
    i += 1
  }
  if i >= chars.length() {
    return Err(Diagnostic::new(InvalidNumber, "Expected a JSON number"))
  }
  if chars[i] == 48 {
    i += 1
  } else if chars[i] >= 49 && chars[i] <= 57 {
    while i < chars.length() && digit(chars[i]) {
      i += 1
    }
  } else {
    return Err(Diagnostic::new(InvalidNumber, "Expected an integer part"))
  }
  if i < chars.length() && chars[i] == 46 {
    i += 1
    let start = i
    while i < chars.length() && digit(chars[i]) {
      i += 1
    }
    if i == start {
      return Err(Diagnostic::new(InvalidNumber, "Expected fractional digits"))
    }
  }
  if i < chars.length() && (chars[i] == 69 || chars[i] == 101) {
    i += 1
    if i < chars.length() && (chars[i] == 43 || chars[i] == 45) {
      i += 1
    }
    let start = i
    while i < chars.length() && digit(chars[i]) {
      i += 1
    }
    if i == start {
      return Err(Diagnostic::new(InvalidNumber, "Expected exponent digits"))
    }
  }
  if i != chars.length() {
    Err(Diagnostic::new(InvalidNumber, "Unexpected number suffix"))
  } else {
    Ok({ token, })
  }
}

///|
fn Number::normalized(self : Number) -> (Bool, String, @bigint.BigInt) {
  let negative = self.token.has_prefix("-")
  let parts = self.token.to_lower().split("e").collect()
  let mantissa = parts[0].to_owned()
  let mut exponent = if parts.length() == 2 {
    let raw = parts[1].to_owned()
    @bigint.BigInt::from_string(
      if raw.has_prefix("+") {
        raw[1:].to_owned()
      } else {
        raw
      },
    )
  } else {
    @bigint.BigInt::from_int(0)
  }
  let digits = StringBuilder()
  let mut after_dot = false
  let mut fraction = 0
  for c in mantissa.code_units() {
    if c == 46 {
      after_dot = true
    } else if digit(c) {
      digits.write_char(c.to_int().unsafe_to_char())
      if after_dot {
        fraction += 1
      }
    }
  }
  exponent = exponent - @bigint.BigInt::from_int(fraction)
  let all = digits.to_string()
  let mut start = 0
  let mut end = all.length()
  while start < end && all.code_unit_at(start) == 48 {
    start += 1
  }
  if start == end {
    return (false, "0", @bigint.BigInt::from_int(0))
  }
  while end > start && all.code_unit_at(end - 1) == 48 {
    end -= 1
    exponent = exponent + @bigint.BigInt::from_int(1)
  }
  (negative, all[start:end].to_owned(), exponent)
}

///|
/// A key that is equal exactly when the numbers are numerically equal, for
/// hashing many values without pairwise comparison.
pub fn Number::numeric_key(self : Number) -> String {
  let (negative, digits, exponent) = self.normalized()
  (if negative { "-" } else { "" }) + digits + "e" + exponent.to_string()
}

///|
pub fn Number::numeric_equal(self : Number, other : Number) -> Bool {
  let a = self.normalized()
  let b = other.normalized()
  a.0 == b.0 && a.1 == b.1 && a.2 == b.2
}

///|
pub fn Number::is_integer(self : Number) -> Bool {
  self.normalized().2.compare_int(0) >= 0
}

///|
/// Compare mathematical values without converting to binary floating point.
pub fn Number::numeric_compare(self : Number, other : Number) -> Int32 {
  let a = self.normalized()
  let b = other.normalized()
  if a.0 != b.0 {
    return if a.0 { -1 } else { 1 }
  }
  if a.1 == "0" {
    return if b.1 == "0" { 0 } else { -1 }
  }
  if b.1 == "0" {
    return 1
  }
  let sign = if a.0 { -1 } else { 1 }
  let order = (a.2 + @bigint.BigInt::from_int(a.1.length())).compare(
    b.2 + @bigint.BigInt::from_int(b.1.length()),
  )
  if order != 0 {
    return sign * order
  }
  let length = if a.1.length() > b.1.length() {
    a.1.length()
  } else {
    b.1.length()
  }
  for i in 0..<length {
    let left = if i < a.1.length() { a.1.code_unit_at(i) } else { 48 }
    let right = if i < b.1.length() { b.1.code_unit_at(i) } else { 48 }
    let order = left.compare(right)
    if order != 0 {
      return sign * order
    }
  }
  0
}
