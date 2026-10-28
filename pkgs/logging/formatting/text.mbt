///|
/// The style of console output.
pub(all) enum Theme {
  /// ANSI colors: muted time, brackets and category, a style for each level,
  /// muted literal text, a style for each JSON type of a bound value, and a
  /// style for error text.
  Literate
  /// No ANSI escape codes.
  Plain
} derive(Eq, Debug)

///|
pub extend Theme with Eq::{equal, not_equal}

///|
pub extend Theme with @debug.Debug::{to_repr}

///|
/// The indent at the start of each continuation line of a message and each line
/// of error text.
const INDENT : String = "    "

///|
/// The ANSI code that removes all styles.
const RESET : String = "\u{1b}[0m"

///|
/// Time, brackets and category: bright black (gray).
const META_STYLE : String = "\u{1b}[90m"

///|
/// Literal message text: white, which is less bright than bound values.
const LITERAL_STYLE : String = "\u{1b}[37m"

///|
/// Error text: bright red.
const ERROR_STYLE : String = "\u{1b}[91m"

///|
/// The style of the level code of `level`.
fn level_style(level : @logging.Level) -> String {
  match level {
    Trace => "\u{1b}[90m"
    Debug => "\u{1b}[37m"
    Information => "\u{1b}[97m"
    Warning => "\u{1b}[93m"
    Error => "\u{1b}[97;41m"
    Critical => "\u{1b}[1;97;41m"
  }
}

///|
/// The style of a bound value, from its JSON type.
fn value_style(value : Json) -> String {
  match value {
    Number(_, ..) => "\u{1b}[95m"
    String(_) => "\u{1b}[96m"
    True | False => "\u{1b}[94m"
    Null => "\u{1b}[34m"
    Array(_) | Object(_) => "\u{1b}[92m"
  }
}

///|
/// The three-letter code of `level`, as in `LogEvent::to_line`.
fn level_code(level : @logging.Level) -> String {
  match level {
    Trace => "TRC"
    Debug => "DBG"
    Information => "INF"
    Warning => "WRN"
    Error => "ERR"
    Critical => "CRT"
  }
}

///|
const HEX_DIGITS : String = "0123456789abcdef"

///|
/// True for a character that `escape_controls` replaces: a C0 control except
/// LF and TAB, DEL, and a C1 control (U+0080 to U+009F).
fn is_unsafe_control(code : Int) -> Bool {
  (code < 0x20 && code != 0x0A && code != 0x09) ||
  code == 0x7F ||
  (code >= 0x80 && code <= 0x9F)
}

///|
/// `text` with each unsafe control character replaced by the visible text
/// `\xNN`, with two lower-case hex digits. For example ESC is `\x1b` and CR is
/// `\x0d`. So caller text cannot send a command to a terminal. LF and TAB stay.
fn escape_controls(text : String) -> String {
  guard text.iter().any(char => is_unsafe_control(char.to_int())) else {
    return text
  }
  let out = StringBuilder()
  for char in text {
    let code = char.to_int()
    if is_unsafe_control(code) {
      out.write_string("\\x")
      out.write_char(HEX_DIGITS.get_char(code / 16).unwrap())
      out.write_char(HEX_DIGITS.get_char(code % 16).unwrap())
    } else {
      out.write_char(char)
    }
  }
  out.to_string()
}

///|
/// A builder of one rendered event that applies the styles of one theme.
priv struct Painter {
  out : StringBuilder
  styled : Bool
}

///|
/// Write `text`, which has no unsafe control characters, in `style`. Each LF
/// starts a continuation line with `INDENT`. Each nonempty piece of a line gets
/// its own style and reset, so no style continues past a line end.
fn Painter::span(self : Painter, style : String, text : String) -> Unit {
  let mut first = true
  for piece in text.split("\n") {
    if !first {
      self.out.write_char('\n')
      self.out.write_string(INDENT)
    }
    first = false
    if piece.is_empty() {
      continue
    }
    if self.styled {
      self.out.write_string(style)
    }
    self.out.write_view(piece)
    if self.styled {
      self.out.write_string(RESET)
    }
  }
}

///|
/// Write `text` with no style.
fn Painter::plain(self : Painter, text : String) -> Unit {
  self.out.write_string(text)
}

///|
/// Write the category and the message of `record`, then each line of its error
/// text, then the final LF.
fn Painter::body(self : Painter, record : LogRecord) -> Unit {
  if record.category is Some(category) {
    self.span(META_STYLE, escape_controls(category) + ":")
    self.plain(" ")
  }
  for segment in record.segments {
    match segment {
      Text(text) => self.span(LITERAL_STYLE, escape_controls(text))
      Value(value~, ..) =>
        self.span(value_style(value), escape_controls(segment.text()))
    }
  }
  if record.error_text is Some(error) {
    self.plain("\n" + INDENT)
    self.span(ERROR_STYLE, escape_controls(error))
  }
  self.plain("\n")
}

///|
/// Render `record` as one console event in `theme`, for example
/// `[14:23:07.012Z INF] workspace.loader: Loaded 3 files from src`, with a final
/// LF. The category and its `: ` are not there when the record has no category.
/// Each continuation line of the message, and each line of the error text, starts
/// with four spaces.
///
/// The renderer replaces each C0 control character except LF and TAB, DEL and
/// each C1 control character (U+0080 to U+009F) in caller text with the visible
/// text `\xNN`, before it adds a style. For example ESC is `\x1b` and the CR of a
/// CR LF pair is `\x0d`. So only the renderer can write ANSI codes. With
/// `Literate`, each styled part ends with a reset, so the event ends with no
/// style before its LF. With `Plain`, the output has no ESC character.
pub fn format_console(record : LogRecord, theme : Theme) -> String {
  let painter = { out: StringBuilder(), styled: theme == Literate }
  painter.span(META_STYLE, "[" + record.timestamp.time_of_day() + " ")
  painter.span(level_style(record.level), level_code(record.level))
  painter.span(META_STYLE, "]")
  painter.plain(" ")
  painter.body(record)
  painter.out.to_string()
}

///|
/// Render `record` as one event of a readable log file, for example
/// `2026-10-27T14:23:07.024Z [INF] workspace.loader: Loaded 3 files from src`,
/// with a final LF. The output has no ANSI codes. The category, the continuation
/// lines and the escape of control characters are as in `format_console`.
pub fn format_text(record : LogRecord) -> String {
  let painter = { out: StringBuilder(), styled: false }
  painter.plain(record.timestamp.to_iso8601())
  painter.plain(" [" + level_code(record.level) + "] ")
  painter.body(record)
  painter.out.to_string()
}
