///|
/// A receiver of log events: the bring-your-own seam of the logging module.
///
/// An application or an adapter implements `log` to send events to any backend.
/// Library code takes a `&Logger` value and does not know the backend. The level
/// methods (`info`, `warn` and the others) ask `enabled` first, and build no event
/// for a level that is not enabled. The default `enabled` enables each level.
///
/// `log` has no error effect. A backend that can fail handles its own failure, so
/// a log call never fails the code that writes it.
pub(open) trait Logger {
  enabled(Self, Level) -> Bool = _
  log(Self, LogEvent) -> Unit
}

///|
impl Logger with enabled(_self, _level) {
  true
}

///|
/// Write one event at `level`: ask `enabled` first, then parse the template, bind
/// `args` to its holes in order, build the event and give it to `log`. A template
/// or argument mismatch never fails and never drops the event. The level methods
/// call this function.
pub fn &Logger::write(
  self : &Logger,
  level : Level,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  guard self.enabled(level) else { return }
  let properties = bind_properties(parse_template(template), args)
  self.log({ level, category: None, template, properties, error })
}

///|
/// Write one `Trace` event. See `&Logger::write`.
pub fn &Logger::trace(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  self.write(Trace, template, args, error?)
}

///|
/// Write one `Debug` event. See `&Logger::write`.
pub fn &Logger::debug(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  self.write(Debug, template, args, error?)
}

///|
/// Write one `Information` event. See `&Logger::write`.
pub fn &Logger::info(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  self.write(Information, template, args, error?)
}

///|
/// Write one `Warning` event. See `&Logger::write`.
pub fn &Logger::warn(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  self.write(Warning, template, args, error?)
}

///|
/// Write one `Error` event. See `&Logger::write`.
pub fn &Logger::error(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  self.write(Error, template, args, error?)
}

///|
/// Write one `Critical` event. See `&Logger::write`.
pub fn &Logger::critical(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit {
  self.write(Critical, template, args, error?)
}
