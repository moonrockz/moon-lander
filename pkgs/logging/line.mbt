///|
/// The three-letter code of `level` in a text line.
fn level_code(level : Level) -> String {
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
/// The event as text: the level code in brackets, the category and a colon when
/// the event has one, and the message text, for example
/// `[INF] morphir.build: Loaded 3 files from src`. When the event has an error, a
/// second line `  error: <text>` gives the `Show` text of the error, so the error
/// type decides what the text holds.
pub fn LogEvent::to_line(self : LogEvent) -> String {
  let out = StringBuilder()
  out.write_string("[\{level_code(self.level)}] ")
  if self.category is Some(category) {
    out.write_string("\{category}: ")
  }
  out.write_string(self.message())
  if self.error is Some(error) {
    out.write_string("\n  error: \{error}")
  }
  out.to_string()
}
