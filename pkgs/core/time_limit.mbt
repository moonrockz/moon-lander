///|
/// The rule of a time limit that an input breaks.
pub enum TimeLimitRule {
  /// The text is empty.
  Empty
  /// A space is at the start or the end, two spaces are next to each other, or
  /// the text holds whitespace that is not a space, such as a tab or a newline.
  UnexpectedSpace
  /// A part does not start with a number such as `10` or `1.5`.
  NotANumber
  /// A number has no unit after it.
  MissingUnit
  /// The unit is not one of the known units.
  UnknownUnit(String)
  /// A part has a larger unit than the part before it.
  UnitsOutOfOrder
  /// Two parts have the same unit.
  RepeatedUnit
  /// A part is not a whole number of milliseconds.
  NotWholeMilliseconds
  /// The value is zero or less.
  NotPositive
  /// The value is more than the largest time limit.
  AboveLargest
} derive(Eq, Debug)

///|
pub extend TimeLimitRule with Eq::{equal, not_equal}

///|
pub extend TimeLimitRule with @debug.Debug::{to_repr}

///|
/// An input that is not a valid time limit. Callers can match the cases, but
/// only the constructors of `TimeLimit` make them.
pub suberror TimeLimitError {
  /// The input `input` breaks the rule `rule`. For a constructor that takes a
  /// count, `input` is the count with its unit, for example `-1ms`.
  InvalidTimeLimit(input~ : String, rule~ : TimeLimitRule)
} derive(Debug)

///|
pub extend TimeLimitError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn TimeLimitError::message(self : TimeLimitError) -> String {
  let InvalidTimeLimit(input~, rule~) = self
  let reason = match rule {
    Empty => "the text is empty"
    UnexpectedSpace =>
      "use at most one space, and only between a number and its unit or between parts"
    NotANumber => "each part must start with a number such as 10 or 1.5"
    MissingUnit => "each number needs a unit, such as ms, s, m or h"
    UnknownUnit(unit) =>
      "the unit \{unit.escape()} is not known; use ms, s, m or h, or millisecond(s), second(s), minute(s) or hour(s)"
    UnitsOutOfOrder => "the parts must go from the largest unit to the smallest"
    RepeatedUnit => "each unit can occur only one time"
    NotWholeMilliseconds => "each part must be a whole number of milliseconds"
    NotPositive => "the value must be greater than zero"
    AboveLargest =>
      "the value must not be more than \{MAX_MILLIS} milliseconds (\{LARGEST_TEXT})"
  }
  "Invalid time limit \{input.escape()}: \{reason}"
}

///|
/// A positive amount of time, from 1 millisecond to 2 147 483 647 milliseconds
/// (the largest `Int`, about 24.8 days). This is the range of the timeouts of
/// `moonbitlang/async`, so `to_millis` can give the value to it.
pub struct TimeLimit {
  priv millis : Int
} derive(Eq, Compare, Hash, Debug)

///|
pub extend TimeLimit with Eq::{equal, not_equal}

///|
pub extend TimeLimit with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend TimeLimit with Hash::{hash, hash_combine}

///|
pub extend TimeLimit with @debug.Debug::{to_repr}

///|
/// The largest time limit in milliseconds.
const MAX_MILLIS : Int64 = 2147483647L

///|
/// The text form of the largest time limit.
const LARGEST_TEXT : String = "596h31m23s647ms"

///|
/// Make a time limit of `count` milliseconds.
pub fn TimeLimit::millis(count : Int) -> TimeLimit raise TimeLimitError {
  from_total("\{count}ms", count.to_int64())
}

///|
/// Make a time limit of `count` seconds.
pub fn TimeLimit::seconds(count : Int) -> TimeLimit raise TimeLimitError {
  from_total("\{count}s", count.to_int64() * 1000L)
}

///|
/// The time limit in milliseconds, from 1 to the largest `Int`.
pub fn TimeLimit::to_millis(self : TimeLimit) -> Int {
  self.millis
}

///|
fn from_total(input : String, total : Int64) -> TimeLimit raise TimeLimitError {
  guard total > 0L else { raise InvalidTimeLimit(input~, rule=NotPositive) }
  guard total <= MAX_MILLIS else {
    raise InvalidTimeLimit(input~, rule=AboveLargest)
  }
  { millis: total.to_int() }
}

///|
/// One part of the text form: the digits before and after the decimal point,
/// and the unit.
priv struct Part {
  whole : String
  fraction : String
  unit : Unit_
}

///|
/// A unit of the text form, from the smallest to the largest.
priv enum Unit_ {
  Millisecond
  Second
  Minute
  Hour
}

///|
fn Unit_::rank(self : Unit_) -> Int {
  match self {
    Millisecond => 0
    Second => 1
    Minute => 2
    Hour => 3
  }
}

///|
fn Unit_::millis(self : Unit_) -> Int64 {
  match self {
    Millisecond => 1L
    Second => 1000L
    Minute => 60_000L
    Hour => 3_600_000L
  }
}

///|
fn unit_of(text : String) -> Unit_? {
  match text {
    "ms" | "millisecond" | "milliseconds" => Some(Millisecond)
    "s" | "second" | "seconds" => Some(Second)
    "m" | "minute" | "minutes" => Some(Minute)
    "h" | "hour" | "hours" => Some(Hour)
    _ => None
  }
}

///|
/// Parse a time limit from its text form: one or more parts, each a decimal
/// number, an optional space and a unit, from the largest unit to the smallest.
/// For example `9ms`, `10 seconds`, `1.5s` and `2m30s`. The units are `ms`,
/// `s`, `m` and `h`, and the lower-case words `millisecond`, `second`, `minute`
/// and `hour`, each also with a final `s`. The checks of the shape come first,
/// then the checks of the unit order, then the checks of the value.
pub fn TimeLimit::parse(text : String) -> TimeLimit raise TimeLimitError {
  fn invalid(rule : TimeLimitRule) -> TimeLimitError {
    InvalidTimeLimit(input=text, rule~)
  }

  let chars = Array::from_iter(text.iter())
  guard chars.length() > 0 else { raise invalid(Empty) }
  guard chars[0] != ' ' &&
    chars[chars.length() - 1] != ' ' &&
    !chars.iter().any(char => char != ' ' && char.is_whitespace()) else {
    raise invalid(UnexpectedSpace)
  }
  // The shape: read each part.
  let parts : Array[Part] = []
  let mut index = 0
  while index < chars.length() {
    let whole = take_while(chars, index, is_digit)
    guard whole.length() > 0 else { raise invalid(NotANumber) }
    index += whole.length()
    let mut fraction = ""
    if index < chars.length() && chars[index] == '.' {
      fraction = take_while(chars, index + 1, is_digit)
      guard fraction.length() > 0 else { raise invalid(NotANumber) }
      index += 1 + fraction.length()
    }
    guard index >= chars.length() || chars[index] != '.' else {
      raise invalid(NotANumber)
    }
    index = skip_one_space(chars, index) catch { _ => raise invalid(UnexpectedSpace) }
    let unit_text = take_while(chars, index, is_unit_char)
    guard unit_text.length() > 0 else { raise invalid(MissingUnit) }
    guard unit_of(unit_text) is Some(unit) else {
      raise invalid(UnknownUnit(unit_text))
    }
    index += unit_text.length()
    parts.push({ whole, fraction, unit })
    index = skip_one_space(chars, index) catch { _ => raise invalid(UnexpectedSpace) }
  }
  // The order: each unit is smaller than the unit before it.
  for i in 1..<parts.length() {
    let before = parts[i - 1].unit.rank()
    let after = parts[i].unit.rank()
    if after == before {
      raise invalid(RepeatedUnit)
    } else if after > before {
      raise invalid(UnitsOutOfOrder)
    }
  }
  // The value. Each part is checked in Int64 after its zeros at the start of
  // the whole digits and at the end of the fraction digits go, so the work is
  // linear in the text and nothing can overflow. A fraction with more than 7
  // digits after that is never a whole number of milliseconds, because the
  // largest unit, 3 600 000 ms, is 2^7 * 3^2 * 5^5. A whole number with more
  // than 10 digits is above the largest limit for every unit.
  let mut total = 0L
  let mut above = false
  for part in parts {
    let whole = trim_char(part.whole, '0', start=true)
    let fraction = trim_char(part.fraction, '0', start=false)
    guard fraction.length() <= 7 else { raise invalid(NotWholeMilliseconds) }
    let unit = part.unit.millis()
    let divisor = power_of_ten(fraction.length())
    let scaled_fraction = digits_value(fraction) * unit
    guard scaled_fraction % divisor == 0L else {
      raise invalid(NotWholeMilliseconds)
    }
    if whole.length() > 10 {
      above = true
    } else {
      total += digits_value(whole) * unit + scaled_fraction / divisor
    }
  }
  guard above || total > 0L else { raise invalid(NotPositive) }
  guard !above && total <= MAX_MILLIS else { raise invalid(AboveLargest) }
  { millis: total.to_int() }
}

///|
/// `text` without the characters `char` at its start or at its end.
fn trim_char(text : String, char : Char, start~ : Bool) -> String {
  let chars = Array::from_iter(text.iter())
  let mut from = 0
  let mut to = chars.length()
  if start {
    while from < to && chars[from] == char {
      from += 1
    }
  } else {
    while to > from && chars[to - 1] == char {
      to -= 1
    }
  }
  String::from_array(chars[from:to].to_owned())
}

///|
/// The value of at most 10 ASCII digits. The empty text is 0.
fn digits_value(digits : String) -> Int64 {
  let mut value = 0L
  for char in digits {
    value = value * 10L + (char.to_int() - '0'.to_int()).to_int64()
  }
  value
}

///|
/// 10 to the power `exponent`, for an exponent from 0 to 7.
fn power_of_ten(exponent : Int) -> Int64 {
  let mut value = 1L
  for _ in 0..<exponent {
    value *= 10L
  }
  value
}

///|
/// The characters from `start` for which `accept` is true, as text.
fn take_while(chars : Array[Char], start : Int, accept : (Char) -> Bool) -> String {
  let builder = StringBuilder()
  let mut index = start
  while index < chars.length() && accept(chars[index]) {
    builder.write_char(chars[index])
    index += 1
  }
  builder.to_string()
}

///|
/// The index after one optional space at `index`. Two spaces raise.
fn skip_one_space(chars : Array[Char], index : Int) -> Int raise {
  guard index < chars.length() && chars[index] == ' ' else { return index }
  guard index + 1 < chars.length() && chars[index + 1] != ' ' else {
    fail("two spaces")
  }
  index + 1
}

///|
fn is_digit(char : Char) -> Bool {
  char >= '0' && char <= '9'
}

///|
/// A character of a unit: anything except an ASCII digit, a space and `.`. So
/// the unit text in an error is the full text that the user wrote, for example
/// `µs` or `séconds`.
fn is_unit_char(char : Char) -> Bool {
  !is_digit(char) && char != ' ' && char != '.'
}

///|
/// The canonical text: the parts from hours to milliseconds with short units
/// and no spaces, without the zero parts, for example `2m30s` or `1s500ms`.
/// `TimeLimit::parse` reads it back to an equal limit.
pub impl Show for TimeLimit with output(self, logger) {
  let mut rest = self.millis
  for unit in [Hour, Minute, Second, Millisecond] {
    let size = unit.millis().to_int()
    let count = rest / size
    rest = rest % size
    if count > 0 {
      logger.write_string(count.to_string())
      logger.write_string(
        match unit {
          Hour => "h"
          Minute => "m"
          Second => "s"
          Millisecond => "ms"
        },
      )
    }
  }
}

///|
pub extend TimeLimit with Show::{output, to_string}
