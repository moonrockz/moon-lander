///|
priv struct NullLogger {}

///|
impl Logger for NullLogger with enabled(_self, _level) {
  false
}

///|
impl Logger for NullLogger with log(_self, _event) {
  ()
}

///|
/// A logger that enables no level and drops each event.
pub fn null_logger() -> &Logger {
  NullLogger::{  }
}

///|
priv struct MinLevel {
  inner : &Logger
  minimum : Level
}

///|
impl Logger for MinLevel with enabled(self, level) {
  level >= self.minimum && self.inner.enabled(level)
}

///|
impl Logger for MinLevel with log(self, event) {
  if Logger::enabled(self, event.level) {
    self.inner.log(event)
  }
}

///|
/// Wrap `logger` with a minimum level. The wrapper enables a level only when the
/// level is `minimum` or higher and `logger` enables it, and passes only the events
/// of an enabled level to `logger`.
pub fn min_level(logger : &Logger, minimum : Level) -> &Logger {
  MinLevel::{ inner: logger, minimum }
}

///|
priv struct FanOut {
  loggers : Array[&Logger]
}

///|
impl Logger for FanOut with enabled(self, level) {
  self.loggers.iter().any(logger => logger.enabled(level))
}

///|
impl Logger for FanOut with log(self, event) {
  for logger in self.loggers {
    if logger.enabled(event.level) {
      logger.log(event)
    }
  }
}

///|
/// A logger that sends each event to each of `loggers`, in list order. It enables a
/// level when one of `loggers` enables it, and gives each event only to the loggers
/// that enable its level. Later changes to the `loggers` array do not change the
/// fan-out.
pub fn fan_out(loggers : Array[&Logger]) -> &Logger {
  FanOut::{ loggers: loggers.copy() }
}

///|
priv struct WithCategory {
  inner : &Logger
  name : String
}

///|
impl Logger for WithCategory with enabled(self, level) {
  self.inner.enabled(level)
}

///|
impl Logger for WithCategory with log(self, event) {
  if Logger::enabled(self, event.level) {
    self.inner.log({ ..event, category: Some(self.name) })
  }
}

///|
/// Wrap `logger` with the category `name`, for example `morphir.build`. The
/// wrapper sets that category on each event and does not change the other fields.
pub fn with_category(logger : &Logger, name : String) -> &Logger {
  WithCategory::{ inner: logger, name }
}
