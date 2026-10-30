///|
/// A point in time, UTC, with nanosecond precision. The caller reads the clock
/// and gives "now" as an `Instant`; the library never reads a clock.
pub struct Instant {
  priv nanos : Int64
} derive(Eq, Compare, Debug)

///|
pub extend Instant with Eq::{equal, not_equal}

///|
pub extend Instant with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend Instant with @debug.Debug::{to_repr}

///|
let nanos_per_second : Int64 = 1_000_000_000L

///|
/// The instant `seconds` after 1970-01-01T00:00:00Z.
pub fn Instant::from_unix_seconds(seconds : Int64) -> Instant {
  { nanos: seconds * nanos_per_second }
}

///|
/// Whole seconds since 1970-01-01T00:00:00Z, rounded down.
pub fn Instant::unix_seconds(self : Instant) -> Int64 {
  let seconds = self.nanos / nanos_per_second
  if self.nanos % nanos_per_second < 0L {
    seconds - 1L
  } else {
    seconds
  }
}

///|
pub impl Show for Instant with output(self, logger) {
  logger.write_string(self.unix_seconds().to_string())
}

///|
pub extend Instant with Show::{output, to_string}

///|
/// Read a protobuf JSON timestamp, for example `2022-12-31T23:59:59.999Z`:
/// RFC 3339 with up to nine fraction digits and a `Z` or `+hh:mm` offset.
fn parse_timestamp(text : String) -> Instant? {
  fn number(start : Int, count : Int) -> Int? {
    guard start + count <= text.length() else { return None }
    let mut value = 0
    for i in start..<(start + count) {
      let code = text[i].to_int()
      guard code >= '0'.to_int() && code <= '9'.to_int() else { return None }
      value = value * 10 + (code - '0'.to_int())
    }
    Some(value)
  }

  fn char_at(at : Int, expected : Char) -> Bool {
    at < text.length() && text[at].to_int() == expected.to_int()
  }

  guard number(0, 4) is Some(year) &&
    char_at(4, '-') &&
    number(5, 2) is Some(month) &&
    char_at(7, '-') &&
    number(8, 2) is Some(day) &&
    char_at(10, 'T') &&
    number(11, 2) is Some(hour) &&
    char_at(13, ':') &&
    number(14, 2) is Some(minute) &&
    char_at(16, ':') &&
    number(17, 2) is Some(second) else {
    return None
  }
  guard year >= 1 &&
    month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= @der.days_in_month(year, month) &&
    hour <= 23 &&
    minute <= 59 &&
    second <= 59 else {
    return None
  }
  let mut at = 19
  let mut fraction = 0L
  if char_at(at, '.') {
    at += 1
    let mut digits = 0
    while at < text.length() &&
          text[at].to_int() >= '0'.to_int() &&
          text[at].to_int() <= '9'.to_int() {
      guard digits < 9 else { return None }
      fraction = fraction * 10L + (text[at].to_int() - '0'.to_int()).to_int64()
      digits += 1
      at += 1
    }
    guard digits > 0 else { return None }
    for _ in digits..<9 {
      fraction = fraction * 10L
    }
  }
  let offset = if char_at(at, 'Z') && at + 1 == text.length() {
    0
  } else if (char_at(at, '+') || char_at(at, '-')) &&
    at + 6 == text.length() &&
    char_at(at + 3, ':') &&
    number(at + 1, 2) is Some(hours) &&
    number(at + 4, 2) is Some(minutes) &&
    hours <= 23 &&
    minutes <= 59 {
    let size = hours * 3600 + minutes * 60
    if char_at(at, '+') {
      size
    } else {
      -size
    }
  } else {
    return None
  }
  let seconds = @der.unix_seconds(year, month, day, hour, minute, second) -
    offset.to_int64()
  Some({ nanos: seconds * nanos_per_second + fraction })
}
