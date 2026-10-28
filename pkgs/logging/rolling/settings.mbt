///|
/// The rule of a file stem that an input breaks.
pub enum StemRule {
  /// The text is empty.
  Empty
  /// The text has more than 64 characters.
  TooLong
  /// The first character is not an ASCII letter.
  NotLetterStart
  /// A character is not an ASCII letter, an ASCII digit, `_` or `-`.
  InvalidCharacter(Char)
  /// The text ends with `_` or `-` and one or more digits, for example
  /// `acme_001` or `acme-20261027`. A file name of a shorter stem has that
  /// form, so two file sets could own the same file.
  NumericSuffix
  /// The text is a Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM0` to
  /// `COM9` or `LPT0` to `LPT9`) in any letter case.
  ReservedDeviceName
} derive(Eq, Debug)

///|
pub extend StemRule with Eq::{equal, not_equal}

///|
pub extend StemRule with @debug.Debug::{to_repr}

///|
/// A count of bytes: a file size or the encoded size of a record. It is zero or
/// more.
pub struct ByteCount {
  priv bytes : Int64
} derive(Eq, Compare, Hash, Debug)

///|
pub extend ByteCount with Eq::{equal, not_equal}

///|
pub extend ByteCount with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend ByteCount with Hash::{hash, hash_combine}

///|
pub extend ByteCount with @debug.Debug::{to_repr}

///|
/// Make a byte count, for example a file size from the file system. It raises
/// `NegativeByteCount` when `bytes` is less than zero.
pub fn ByteCount::of(bytes : Int64) -> ByteCount raise RollingError {
  guard bytes >= 0L else { raise NegativeByteCount(bytes~) }
  { bytes, }
}

///|
/// The count of UTF-8 bytes of `text`, for example a rendered record with its
/// LF.
pub fn ByteCount::of_text(text : String) -> ByteCount {
  { bytes: @formatting.utf8_length(text) }
}

///|
/// No bytes.
pub fn ByteCount::zero() -> ByteCount {
  { bytes: 0L }
}

///|
/// The count as a number.
pub fn ByteCount::to_int64(self : ByteCount) -> Int64 {
  self.bytes
}

///|
/// The count as text, for example `2048`.
pub impl Show for ByteCount with output(self, logger) {
  logger.write_string(self.bytes.to_string())
}

///|
pub extend ByteCount with Show::{output, to_string}

///|
/// A rolling input that breaks a rule, or a file set that has no next file
/// name. Callers can match the cases, but only this package makes them.
pub suberror RollingError {
  /// The stem `input` breaks the rule `rule`.
  InvalidStem(input~ : String, rule~ : StemRule)
  /// The file byte limit `bytes` is zero or less.
  NotPositiveByteLimit(bytes~ : Int64)
  /// The retained file count `count` is zero or less.
  NotPositiveFileCount(count~ : Int)
  /// The byte count `bytes` is less than zero.
  NegativeByteCount(bytes~ : Int64)
  /// The file `last` has the largest sequence number, so the period has no
  /// next file name. The file set does not use a name again.
  SequenceExhausted(last~ : String)
} derive(Debug)

///|
pub extend RollingError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn RollingError::message(self : RollingError) -> String {
  match self {
    InvalidStem(input~, rule~) => {
      let reason = match rule {
        Empty => "the text is empty"
        TooLong => "the text must have at most \{MAX_STEM_LENGTH} characters"
        NotLetterStart => "the first character must be an ASCII letter"
        InvalidCharacter(char) =>
          "the character \{char.to_string().escape()} is not an ASCII letter, an ASCII digit, _ or -"
        NumericSuffix =>
          "the text must not end with _ or - and digits, because the file names of another stem have that form"
        ReservedDeviceName => "the text is a reserved Windows device name"
      }
      "Invalid log file stem \{input.escape()}: \{reason}"
    }
    NotPositiveByteLimit(bytes~) =>
      "Invalid file byte limit \{bytes}: the value must be greater than zero"
    NotPositiveFileCount(count~) =>
      "Invalid retained file count \{count}: the value must be greater than zero"
    NegativeByteCount(bytes~) =>
      "Invalid byte count \{bytes}: the value must not be less than zero"
    SequenceExhausted(last~) =>
      "No file name after \{last.escape()}: the sequence number is at its largest value"
  }
}

///|
/// The largest number of characters in a stem.
const MAX_STEM_LENGTH : Int = 64

///|
/// The first part of each file name of a file set, for example `acme` in
/// `acme-20261027.log`. It has 1 to 64 characters: an ASCII letter, then ASCII
/// letters, ASCII digits, `_` and `-`. It does not end with `_` or `-` and
/// digits, and it is not a Windows device name. So the file names are valid on
/// each OS, and two stems never make the same file name.
pub struct LogFileStem {
  priv text : String
} derive(Eq, Compare, Hash, Debug)

///|
pub extend LogFileStem with Eq::{equal, not_equal}

///|
pub extend LogFileStem with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend LogFileStem with Hash::{hash, hash_combine}

///|
pub extend LogFileStem with @debug.Debug::{to_repr}

///|
fn is_ascii_letter(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
}

///|
fn is_ascii_digit(char : Char) -> Bool {
  char >= '0' && char <= '9'
}

///|
/// Parse a file stem. The checks are in the order of the cases of `StemRule`.
pub fn LogFileStem::parse(text : String) -> LogFileStem raise RollingError {
  fn invalid(rule : StemRule) -> RollingError {
    InvalidStem(input=text, rule~)
  }

  let chars = text.to_array()
  guard chars.length() > 0 else { raise invalid(Empty) }
  guard chars.length() <= MAX_STEM_LENGTH else { raise invalid(TooLong) }
  guard is_ascii_letter(chars[0]) else { raise invalid(NotLetterStart) }
  for char in chars {
    guard is_ascii_letter(char) ||
      is_ascii_digit(char) ||
      char == '_' ||
      char == '-' else {
      raise invalid(InvalidCharacter(char))
    }
  }
  let mut digits_start = chars.length()
  while digits_start > 0 && is_ascii_digit(chars[digits_start - 1]) {
    digits_start -= 1
  }
  guard digits_start == chars.length() ||
    !(chars[digits_start - 1] == '_' || chars[digits_start - 1] == '-') else {
    raise invalid(NumericSuffix)
  }
  guard !is_device_name(text.to_upper()) else {
    raise invalid(ReservedDeviceName)
  }
  { text, }
}

///|
/// True when `upper`, in upper case, is a Windows device name.
fn is_device_name(upper : String) -> Bool {
  match upper {
    "CON" | "PRN" | "AUX" | "NUL" => true
    _ => {
      let chars = upper.to_array()
      chars.length() == 4 &&
      is_ascii_digit(chars[3]) &&
      (String::from_array(chars[0:3]) is ("COM" | "LPT"))
    }
  }
}

///|
/// The stem text.
pub impl Show for LogFileStem with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend LogFileStem with Show::{output, to_string}

///|
/// The size at which a file rolls: a positive number of bytes.
pub struct FileByteLimit {
  priv bytes : Int64
} derive(Eq, Compare, Hash, Debug)

///|
pub extend FileByteLimit with Eq::{equal, not_equal}

///|
pub extend FileByteLimit with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend FileByteLimit with Hash::{hash, hash_combine}

///|
pub extend FileByteLimit with @debug.Debug::{to_repr}

///|
/// Make a limit of `bytes` bytes. The value must be greater than zero.
pub fn FileByteLimit::bytes(bytes : Int64) -> FileByteLimit raise RollingError {
  guard bytes > 0L else { raise NotPositiveByteLimit(bytes~) }
  { bytes, }
}

///|
/// The default limit: 10 MiB (10 485 760 bytes).
pub fn FileByteLimit::default() -> FileByteLimit {
  { bytes: 10L * 1024L * 1024L }
}

///|
/// The limit in bytes, greater than zero.
pub fn FileByteLimit::to_int64(self : FileByteLimit) -> Int64 {
  self.bytes
}

///|
/// The number of newest files that retention keeps, including the active file:
/// a positive count.
pub struct RetainedFileCount {
  priv count : Int
} derive(Eq, Compare, Hash, Debug)

///|
pub extend RetainedFileCount with Eq::{equal, not_equal}

///|
pub extend RetainedFileCount with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend RetainedFileCount with Hash::{hash, hash_combine}

///|
pub extend RetainedFileCount with @debug.Debug::{to_repr}

///|
/// Make a count of `count` files. The value must be greater than zero.
pub fn RetainedFileCount::count(count : Int) -> RetainedFileCount raise RollingError {
  guard count > 0 else { raise NotPositiveFileCount(count~) }
  { count, }
}

///|
/// The default count: 31 files.
pub fn RetainedFileCount::default() -> RetainedFileCount {
  { count: 31 }
}

///|
/// The count, greater than zero.
pub fn RetainedFileCount::to_int(self : RetainedFileCount) -> Int {
  self.count
}

///|
/// When a file set starts a new file. Periods are UTC days.
pub(all) enum RollingPolicy {
  /// A new file for each UTC day, of any size.
  Daily
  /// A new file when the next record would make the file larger than the
  /// limit. The UTC day has no effect.
  Size(FileByteLimit)
  /// A new file for each UTC day, and in a day also at the size limit.
  DailyAndSize(FileByteLimit)
} derive(Eq, Debug)

///|
pub extend RollingPolicy with Eq::{equal, not_equal}

///|
pub extend RollingPolicy with @debug.Debug::{to_repr}

///|
/// The default policy: a new file for each UTC day and at 10 MiB.
pub fn RollingPolicy::default() -> RollingPolicy {
  DailyAndSize(FileByteLimit::default())
}

///|
/// Which old files of a file set stay after a roll.
pub(all) enum Retention {
  /// Keep this number of the newest files, including the active file.
  KeepNewest(RetainedFileCount)
  /// Keep all files.
  KeepAll
} derive(Eq, Debug)

///|
pub extend Retention with Eq::{equal, not_equal}

///|
pub extend Retention with @debug.Debug::{to_repr}

///|
/// The default retention: the newest 31 files, including the active file.
pub fn Retention::default() -> Retention {
  KeepNewest(RetainedFileCount::default())
}

///|
/// The format of the records in the files of a file set.
pub(all) enum FileFormat {
  /// Readable text, from `@formatting.format_text`.
  Text
  /// JSON Lines, from `@formatting.format_json_line`.
  JsonLines
} derive(Eq, Debug)

///|
pub extend FileFormat with Eq::{equal, not_equal}

///|
pub extend FileFormat with @debug.Debug::{to_repr}

///|
/// The default format: readable text.
pub fn FileFormat::default() -> FileFormat {
  Text
}

///|
/// The file name extension of the format, without the dot: `log` or `jsonl`.
pub fn FileFormat::extension(self : FileFormat) -> String {
  match self {
    Text => "log"
    JsonLines => "jsonl"
  }
}
