///|
/// A time that is not in the range of `LogTimestamp`. Callers can match the
/// case, but only `LogTimestamp::from_epoch_millis` makes it.
pub suberror TimestampError {
  /// The input `millis` is before 1970-01-01T00:00:00.000Z or after
  /// 9999-12-31T23:59:59.999Z.
  TimestampOutOfRange(millis~ : Int64)
} derive(Debug)

///|
pub extend TimestampError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn TimestampError::message(self : TimestampError) -> String {
  let TimestampOutOfRange(millis~) = self
  "Invalid log timestamp \{millis}: the value must be from \{EARLIEST_MILLIS} (1970-01-01T00:00:00.000Z) to \{LATEST_MILLIS} (9999-12-31T23:59:59.999Z) milliseconds after the Unix epoch"
}

///|
/// A UTC time of a log record, in whole milliseconds after the Unix epoch, from
/// 1970-01-01T00:00:00.000Z to 9999-12-31T23:59:59.999Z. In this range each
/// time has a four-digit year, so the text forms all have one length and sort
/// in time order.
pub struct LogTimestamp {
  priv millis : Int64
} derive(Eq, Compare, Debug, Hash)

///|
pub extend LogTimestamp with Eq::{equal, not_equal}

///|
pub extend LogTimestamp with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend LogTimestamp with Hash::{hash, hash_combine}

///|
pub extend LogTimestamp with @debug.Debug::{to_repr}

///|
/// The earliest time in milliseconds: 1970-01-01T00:00:00.000Z.
const EARLIEST_MILLIS : Int64 = 0L

///|
/// The latest time in milliseconds: 9999-12-31T23:59:59.999Z.
const LATEST_MILLIS : Int64 = 253402300799999L

///|
/// The milliseconds in one day.
const MILLIS_PER_DAY : Int64 = 86400000L

///|
/// Make a timestamp from `millis` milliseconds after
/// 1970-01-01T00:00:00.000Z. The value must be from 0 to 253402300799999
/// (9999-12-31T23:59:59.999Z).
pub fn LogTimestamp::from_epoch_millis(
  millis : Int64,
) -> LogTimestamp raise TimestampError {
  guard millis >= EARLIEST_MILLIS && millis <= LATEST_MILLIS else {
    raise TimestampOutOfRange(millis~)
  }
  { millis, }
}

///|
/// The earliest timestamp: 1970-01-01T00:00:00.000Z.
pub fn LogTimestamp::earliest() -> LogTimestamp {
  { millis: EARLIEST_MILLIS }
}

///|
/// The latest timestamp: 9999-12-31T23:59:59.999Z.
pub fn LogTimestamp::latest() -> LogTimestamp {
  { millis: LATEST_MILLIS }
}

///|
/// The milliseconds after 1970-01-01T00:00:00.000Z.
pub fn LogTimestamp::epoch_millis(self : LogTimestamp) -> Int64 {
  self.millis
}

///|
/// The whole UTC days after 1970-01-01, from 0 to 2932896 (9999-12-31).
pub fn LogTimestamp::epoch_day(self : LogTimestamp) -> Int64 {
  self.millis / MILLIS_PER_DAY
}

///|
/// The UTC date of the timestamp as year, month (1 to 12) and day (1 to 31).
/// This is the civil-from-days algorithm of Howard Hinnant, for days that are
/// not negative.
fn LogTimestamp::date(self : LogTimestamp) -> (Int64, Int64, Int64) {
  let shifted = self.epoch_day() + 719468L
  let era = shifted / 146097L
  let day_of_era = shifted - era * 146097L
  let year_of_era = (day_of_era -
    day_of_era / 1460L +
    day_of_era / 36524L -
    day_of_era / 146096L) /
    365L
  let day_of_year = day_of_era -
    (365L * year_of_era + year_of_era / 4L - year_of_era / 100L)
  let shifted_month = (5L * day_of_year + 2L) / 153L
  let day = day_of_year - (153L * shifted_month + 2L) / 5L + 1L
  let month = if shifted_month < 10L {
    shifted_month + 3L
  } else {
    shifted_month - 9L
  }
  let year = year_of_era + era * 400L + (if month <= 2L { 1L } else { 0L })
  (year, month, day)
}

///|
/// `value` as decimal text with zeros at the start to `width` digits.
fn padded(value : Int64, width : Int) -> String {
  let text = value.to_string()
  if text.length() >= width {
    text
  } else {
    String::make(width - text.length(), '0') + text
  }
}

///|
/// The UTC date as eight digits, for example `20261027`.
pub fn LogTimestamp::compact_date(self : LogTimestamp) -> String {
  let (year, month, day) = self.date()
  padded(year, 4) + padded(month, 2) + padded(day, 2)
}

///|
/// The UTC time of day with milliseconds and the zone `Z`, for example
/// `14:23:07.024Z`.
pub fn LogTimestamp::time_of_day(self : LogTimestamp) -> String {
  let in_day = self.millis % MILLIS_PER_DAY
  let hours = in_day / 3600000L
  let minutes = in_day / 60000L % 60L
  let seconds = in_day / 1000L % 60L
  let millis = in_day % 1000L
  "\{padded(hours, 2)}:\{padded(minutes, 2)}:\{padded(seconds, 2)}.\{padded(millis, 3)}Z"
}

///|
/// The timestamp in ISO 8601 form with milliseconds and the zone `Z`, for
/// example `2026-10-27T14:23:07.024Z`.
pub fn LogTimestamp::to_iso8601(self : LogTimestamp) -> String {
  let (year, month, day) = self.date()
  "\{padded(year, 4)}-\{padded(month, 2)}-\{padded(day, 2)}T\{self.time_of_day()}"
}

///|
/// The ISO 8601 text, as `to_iso8601` gives it.
pub impl Show for LogTimestamp with output(self, logger) {
  logger.write_string(self.to_iso8601())
}

///|
pub extend LogTimestamp with Show::{output, to_string}
