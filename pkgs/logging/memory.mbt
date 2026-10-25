///|
/// A logger that keeps each event it gets, in the order it gets them. It is for
/// tests and examples: it holds all events in memory and never drops one.
pub struct MemoryLogger {
  priv kept : Array[LogEvent]
}

///|
/// A new in-memory logger with no events.
pub fn MemoryLogger::new() -> MemoryLogger {
  { kept: [] }
}

///|
/// A copy of the kept events, the first event first.
pub fn MemoryLogger::events(self : MemoryLogger) -> Array[LogEvent] {
  self.kept.copy()
}

///|
/// Keep `event` after the events that the logger already holds.
pub impl Logger for MemoryLogger with log(self, event) {
  self.kept.push(event)
}

///|
pub extend MemoryLogger with Logger::{enabled, log}
