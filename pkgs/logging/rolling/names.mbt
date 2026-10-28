///|
/// The largest sequence number of a file in one period.
const MAX_SEQUENCE : Int = 2147483647

///|
/// The files of one stem and one format in a log directory, with one rolling
/// policy. A file set owns only the names of its complete naming scheme. For the
/// stem `acme`:
///
/// | Policy | First file | Next files |
/// | --- | --- | --- |
/// | `Daily` or `DailyAndSize` | `acme-20261027.log` | `acme-20261027_001.log`, `acme-20261027_002.log` |
/// | `Size` | `acme.log` | `acme_001.log`, `acme_002.log` |
///
/// `JsonLines` uses `.jsonl` in place of `.log`. A sequence number has at least
/// three digits, and has more digits after 999 (`_1000`).
pub struct FileSet {
  priv stem : LogFileStem
  priv format : FileFormat
  priv policy : RollingPolicy
} derive(Eq, Debug)

///|
pub extend FileSet with Eq::{equal, not_equal}

///|
pub extend FileSet with @debug.Debug::{to_repr}

///|
/// Make the file set of `stem` and `format` that rolls by `policy`.
pub fn FileSet::new(
  stem : LogFileStem,
  format : FileFormat,
  policy : RollingPolicy,
) -> FileSet {
  { stem, format, policy }
}

///|
/// The stem of the file names.
pub fn FileSet::stem(self : FileSet) -> LogFileStem {
  self.stem
}

///|
/// The format of the records.
pub fn FileSet::format(self : FileSet) -> FileFormat {
  self.format
}

///|
/// The rolling policy.
pub fn FileSet::policy(self : FileSet) -> RollingPolicy {
  self.policy
}

///|
/// The name of the ownership marker of the file set, for example
/// `acme.log.lock`. It does not have the form of an owned file name, so
/// retention never deletes it. The same stem and format with a different policy
/// has the same marker, so one directory cannot mix policies for one file set.
pub fn FileSet::marker_name(self : FileSet) -> String {
  "\{self.stem}.\{self.format.extension()}.lock"
}

///|
/// True when the file names have a UTC date.
fn FileSet::is_daily(self : FileSet) -> Bool {
  self.policy is (Daily | DailyAndSize(_))
}

///|
/// The size limit of the policy, or `None` for `Daily`.
fn FileSet::limit(self : FileSet) -> FileByteLimit? {
  match self.policy {
    Daily => None
    Size(limit) | DailyAndSize(limit) => Some(limit)
  }
}

///|
/// One UTC day of a dated file name: the days after 1970-01-01 and the date as
/// eight digits.
priv struct Period {
  day : Int64
  date : String
} derive(Eq, Compare, Hash, Debug)

///|
/// The name of one file that a file set owns: an optional UTC day and a sequence
/// number, where 0 is the name with no number. Names of one file set sort by day
/// and then by sequence number.
pub struct LogFileName {
  priv period : Period?
  priv sequence : Int
  priv text : String
} derive(Eq, Compare, Hash, Debug)

///|
pub extend LogFileName with Eq::{equal, not_equal}

///|
pub extend LogFileName with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend LogFileName with Hash::{hash, hash_combine}

///|
pub extend LogFileName with @debug.Debug::{to_repr}

///|
/// The UTC day of the name as days after 1970-01-01, as
/// `LogTimestamp::epoch_day` gives it, or `None` for a name with no date.
pub fn LogFileName::epoch_day(self : LogFileName) -> Int64? {
  self.period.map(period => period.day)
}

///|
/// The sequence number in the period: 0 for the name with no number, then 1 for
/// `_001` and so on.
pub fn LogFileName::sequence(self : LogFileName) -> Int {
  self.sequence
}

///|
/// The file name, for example `acme-20261027_001.log`.
pub impl Show for LogFileName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend LogFileName with Show::{output, to_string}

///|
/// The text of a sequence number in a name: nothing for 0, else `_` and at
/// least three digits.
fn sequence_text(sequence : Int) -> String {
  if sequence == 0 {
    ""
  } else if sequence < 10 {
    "_00\{sequence}"
  } else if sequence < 100 {
    "_0\{sequence}"
  } else {
    "_\{sequence}"
  }
}

///|
/// The name of the file set in `period` with `sequence`.
fn FileSet::make_name(
  self : FileSet,
  period : Period?,
  sequence : Int,
) -> LogFileName {
  let date = match period {
    Some(period) => "-" + period.date
    None => ""
  }
  let text = "\{self.stem}\{date}\{sequence_text(sequence)}.\{self.format.extension()}"
  { period, sequence, text }
}

///|
/// The first name of the period of `now`: with its UTC date for a daily policy.
fn FileSet::first_name(self : FileSet, now : @formatting.LogTimestamp) -> LogFileName {
  let period = if self.is_daily() {
    Some({ day: now.epoch_day(), date: now.compact_date() })
  } else {
    None
  }
  self.make_name(period, 0)
}

///|
/// The name after `name` in its period.
fn FileSet::next_name(
  self : FileSet,
  name : LogFileName,
) -> LogFileName raise RollingError {
  guard name.sequence < MAX_SEQUENCE else {
    raise SequenceExhausted(last=name.text)
  }
  self.make_name(name.period, name.sequence + 1)
}

///|
/// The number of days in `month` of `year`.
fn days_in_month(year : Int64, month : Int64) -> Int64 {
  match month {
    2L =>
      if (year % 4L == 0L && year % 100L != 0L) || year % 400L == 0L {
        29L
      } else {
        28L
      }
    4L | 6L | 9L | 11L => 30L
    _ => 31L
  }
}

///|
/// The days after 1970-01-01 of a valid date from the year 1970. This is the
/// days-from-civil algorithm of Howard Hinnant.
fn days_from_civil(year : Int64, month : Int64, day : Int64) -> Int64 {
  let shifted_year = if month <= 2L { year - 1L } else { year }
  let era = shifted_year / 400L
  let year_of_era = shifted_year - era * 400L
  let shifted_month = if month > 2L { month - 3L } else { month + 9L }
  let day_of_year = (153L * shifted_month + 2L) / 5L + day - 1L
  let day_of_era = year_of_era * 365L +
    year_of_era / 4L -
    year_of_era / 100L +
    day_of_year
  era * 146097L + day_of_era - 719468L
}

///|
/// The value of the ASCII digits `chars`.
fn digits_value(chars : ArrayView[Char]) -> Int64 {
  let mut value = 0L
  for char in chars {
    value = value * 10L + (char.to_int() - '0'.to_int()).to_int64()
  }
  value
}

///|
/// The period of eight date digits `YYYYMMDD`, or `None` when they are not a
/// date from 1970-01-01 to 9999-12-31.
fn period_of(digits : ArrayView[Char]) -> Period? {
  let year = digits_value(digits[0:4])
  let month = digits_value(digits[4:6])
  let day = digits_value(digits[6:8])
  guard year >= 1970L &&
    month >= 1L &&
    month <= 12L &&
    day >= 1L &&
    day <= days_in_month(year, month) else {
    return None
  }
  Some({
    day: days_from_civil(year, month, day),
    date: String::from_array(digits),
  })
}

///|
/// The owned name `text`, or `None` when `text` does not have the complete form
/// of a name of this file set. The check is exact: the stem with the same
/// letter case, a real date for a daily policy, a sequence number in its one
/// text form (`_001`, not `_01`, `_0001` or `_000`) and the extension of the
/// format. So `acme-old.log`, `acme-20261027.log.bak`, `acmex.log`, the names of
/// another stem or format and the marker are not owned.
pub fn FileSet::parse_name(self : FileSet, text : String) -> LogFileName? {
  let chars = text.to_array()
  let stem = self.stem.text.to_array()
  guard chars.length() > stem.length() &&
    chars[0:stem.length()] == stem[:] else {
    return None
  }
  let mut index = stem.length()
  let period = if self.is_daily() {
    guard index + 9 <= chars.length() &&
      chars[index] == '-' &&
      chars[index + 1:index + 9].iter().all(is_ascii_digit) else {
      return None
    }
    guard period_of(chars[index + 1:index + 9]) is Some(period) else {
      return None
    }
    index += 9
    Some(period)
  } else {
    None
  }
  let mut sequence = 0
  if index < chars.length() && chars[index] == '_' {
    let start = index + 1
    let mut end = start
    while end < chars.length() && is_ascii_digit(chars[end]) {
      end += 1
    }
    guard end - start >= 3 && end - start <= 10 else { return None }
    let value = digits_value(chars[start:end])
    guard value >= 1L && value <= MAX_SEQUENCE.to_int64() else { return None }
    sequence = value.to_int()
    guard sequence_text(sequence) == "_" + String::from_array(chars[start:end]) else {
      return None
    }
    index = end
  }
  guard String::from_array(chars[index:]) == "." + self.format.extension() else {
    return None
  }
  Some({ period, sequence, text })
}
