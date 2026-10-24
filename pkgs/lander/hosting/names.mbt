///|
/// A fault in the program that sets up a host: a name, a code or a service set
/// that breaks its rules.
pub(all) suberror HostError {
  /// The text is not a valid application name.
  InvalidAppName(text~ : String, reason~ : String)
  /// The text is not a valid service name.
  InvalidServiceName(text~ : String, reason~ : String)
  /// The builder already has the service `existing`, whose name equals `name`
  /// or differs from it only in letter case.
  DuplicateService(name~ : ServiceName, existing~ : ServiceName)
  /// The number is not in the exit code range 0 to 255.
  InvalidExitCode(code~ : Int)
} derive(Debug)

///|
pub extend HostError with @debug.Debug::{to_repr}

///|
/// Text for people that describes the fault.
pub fn HostError::message(self : HostError) -> String {
  match self {
    InvalidAppName(text~, reason~) =>
      "Invalid application name \{text.escape()}: \{reason}"
    InvalidServiceName(text~, reason~) =>
      "Invalid service name \{text.escape()}: \{reason}"
    DuplicateService(name~, existing~) =>
      if name == existing {
        "The host already has a service named \{name.to_string().escape()}"
      } else {
        "The host already has a service named \{existing.to_string().escape()}; \{name.to_string().escape()} differs from it only in letter case"
      }
    InvalidExitCode(code~) =>
      "Invalid exit code \{code}: an exit code is in the range 0 to 255"
  }
}

///|
/// The name of an application. It starts with an ASCII letter, and holds only
/// ASCII letters, digits, `-` and `_`. So it is safe in file and directory
/// names, and it gives a valid environment-variable prefix.
pub struct AppName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend AppName with Eq::{equal, not_equal}

///|
pub extend AppName with Hash::{hash, hash_combine}

///|
pub extend AppName with @debug.Debug::{to_repr}

///|
/// Parse an application name, for example `acme` or `my-tool`.
pub fn AppName::parse(text : String) -> AppName raise HostError {
  fn invalid(reason : String) -> HostError {
    InvalidAppName(text~, reason~)
  }

  guard text.iter().head() is Some(first) else {
    raise invalid("the name is empty")
  }
  guard is_ascii_letter(first) else {
    raise invalid("the name must start with an ASCII letter")
  }
  for char in text {
    guard is_name_char(char) else {
      raise invalid(
        "the character \{char.to_string().escape()} is not allowed; use ASCII letters, digits, '-' and '_'",
      )
    }
  }
  { text, }
}

///|
/// The name as text, which `AppName::parse` reads back to an equal name.
pub impl Show for AppName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend AppName with Show::{output, to_string}

///|
/// The name of a hosted service. It is safe as one component of a file path on
/// Linux, macOS and Windows:
///
/// - It starts with a character that Unicode allows at the start of an
///   identifier (`XID_Start`: letters and letter numbers).
/// - The other characters are identifier characters (`XID_Continue`: letters,
///   combining marks, digits, `_` and a few connector characters such as `·`),
///   `-` or `.`. So it has no path separator, no reserved punctuation, no
///   whitespace and no control or direction character.
/// - It has no invisible identifier character, such as a zero-width joiner, a
///   variation selector or a Hangul filler. A name that looks blank or looks
///   like another name cannot occur, and macOS HFS+ cannot ignore part of it.
/// - It does not end with `.`, which Windows removes.
/// - It is not a Windows device name such as `CON` or `com1`, also not before
///   an extension, as in `nul.log`.
/// - It is at most 128 bytes in UTF-8, so a file name with a prefix or an
///   extension stays under the 255-byte limit.
///
/// The parse does not normalize the text. Two names that differ only in their
/// Unicode normalization form are different names.
pub struct ServiceName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend ServiceName with Eq::{equal, not_equal}

///|
pub extend ServiceName with Hash::{hash, hash_combine}

///|
pub extend ServiceName with @debug.Debug::{to_repr}

///|
/// The longest service name in UTF-8 bytes.
const MAX_SERVICE_NAME_BYTES : Int = 128

///|
/// Parse a service name, for example `db`, `db.primary` or `données`.
pub fn ServiceName::parse(text : String) -> ServiceName raise HostError {
  fn invalid(reason : String) -> HostError {
    InvalidServiceName(text~, reason~)
  }

  guard text.iter().head() is Some(first) else {
    raise invalid("the name is empty")
  }
  guard @xid.is_xid_start(first) && !is_invisible(first) else {
    raise invalid("the name must start with a letter")
  }
  let mut bytes = 0
  let mut last = first
  for char in text {
    guard @xid.is_xid_continue(char) || char == '-' || char == '.' else {
      raise invalid(
        "the character \{char.to_string().escape()} is not allowed; use letters, combining marks, digits, '_', '-' and '.'",
      )
    }
    if is_invisible(char) {
      raise invalid(
        "the character \{char.to_string().escape()} is not allowed; it is invisible",
      )
    }
    bytes += utf8_length(char)
    last = char
  }
  if last == '.' {
    raise invalid("the name must not end with '.'")
  }
  if bytes > MAX_SERVICE_NAME_BYTES {
    raise invalid(
      "the name is \{bytes} bytes in UTF-8; the limit is \{MAX_SERVICE_NAME_BYTES}",
    )
  }
  if is_windows_device_name(text) {
    raise invalid("the name is a Windows device name")
  }
  { text, }
}

///|
/// The name as text, which `ServiceName::parse` reads back to an equal name.
pub impl Show for ServiceName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ServiceName with Show::{output, to_string}

///|
/// A value that gives a service name: a `ServiceName`, or a `String` that
/// `ServiceName::parse` reads. So `service` takes either, and parses text at the
/// boundary. After that step, the host holds only the `ServiceName`.
pub trait IntoServiceName {
  into_service_name(Self) -> ServiceName raise HostError
}

///|
pub impl IntoServiceName for ServiceName with into_service_name(self) {
  self
}

///|
pub extend ServiceName with IntoServiceName::{into_service_name}

///|
pub impl IntoServiceName for String with into_service_name(self) {
  ServiceName::parse(self)
}

///|
/// Whether two names give the same file on a file system that ignores case:
/// Windows compares names by their uppercase form, and macOS by case folding.
fn ServiceName::same_file(self : ServiceName, other : ServiceName) -> Bool {
  fold_case(self.text) == fold_case(other.text)
}

///|
/// The lowercase of the uppercase of each character. Two names that differ only
/// in letter case give the same text, also for pairs whose case mappings are
/// not symmetric, such as `Σ`, `σ` and `ς`, `µ` and `μ`, or `ſ` and `s`.
fn fold_case(text : String) -> String {
  let builder = StringBuilder()
  for char in text {
    for upper in @case_mapping.full_uppercase(char) {
      builder.write_string(@case_mapping.full_lowercase(upper))
    }
  }
  builder.to_string()
}

///|
/// Whether `char` is an identifier character that does not show: a Unicode
/// default-ignorable code point that `XID_Continue` allows, or a Hangul filler.
fn is_invisible(char : Char) -> Bool {
  char
  is (
    '\u{034F}'
    | '\u{115F}'..='\u{1160}'
    | '\u{17B4}'..='\u{17B5}'
    | '\u{180B}'..='\u{180F}'
    | '\u{200C}'..='\u{200D}'
    | '\u{3164}'
    | '\u{FE00}'..='\u{FE0F}'
    | '\u{FFA0}'
    | '\u{E0100}'..='\u{E01EF}'
  )
}

///|
/// The number of bytes that `char` takes in UTF-8.
fn utf8_length(char : Char) -> Int {
  let code = char.to_int()
  if code < 0x80 {
    1
  } else if code < 0x800 {
    2
  } else if code < 0x10000 {
    3
  } else {
    4
  }
}

///|
/// Whether the part before the first `.` is a name that Windows reserves for a
/// device: `CON`, `PRN`, `AUX`, `NUL`, `COM0` to `COM9` and `LPT0` to `LPT9`,
/// in any letter case. Windows also reserves `COM` and `LPT` with a superscript
/// digit, but a service name cannot hold a superscript digit.
fn is_windows_device_name(text : String) -> Bool {
  let base = match text.find(".") {
    Some(index) => text.view(end_offset=index).to_owned()
    None => text
  }
  let upper = base.to_upper()
  if upper is ("CON" | "PRN" | "AUX" | "NUL") {
    return true
  }
  let chars = Array::from_iter(upper.iter())
  chars.length() == 4 &&
  (upper.has_prefix("COM") || upper.has_prefix("LPT")) &&
  (chars[3] is ('0'..='9'))
}

///|
fn is_ascii_letter(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
}

///|
/// An ASCII letter, an ASCII digit, `-` or `_`.
fn is_name_char(char : Char) -> Bool {
  is_ascii_letter(char) || (char >= '0' && char <= '9') || char == '-' || char == '_'
}
