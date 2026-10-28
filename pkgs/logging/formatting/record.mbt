///|
/// One captured log event with its time. `capture` reads all parts of the event
/// one time, including the `Show` text of its error, so the record cannot change
/// after it is made. Each sink of one session renders the same record.
pub struct LogRecord {
  priv timestamp : LogTimestamp
  priv level : @logging.Level
  priv category : String?
  priv template : String
  priv message : String
  priv segments : Array[@logging.MessageSegment]
  priv properties : Array[(String, Json)]
  priv error_text : String?
}

///|
/// Capture `event` at `timestamp`. The error text is the `Show` text of the
/// error now, so a later change to a mutable error does not change the record.
pub fn LogRecord::capture(
  event : @logging.LogEvent,
  timestamp : LogTimestamp,
) -> LogRecord {
  {
    timestamp,
    level: event.level,
    category: event.category,
    template: event.template,
    message: event.message(),
    segments: event.segments(),
    properties: event.properties(),
    error_text: event.error.map(error => "\{error}"),
  }
}

///|
/// The time at which the session got the event.
pub fn LogRecord::timestamp(self : LogRecord) -> LogTimestamp {
  self.timestamp
}

///|
/// The severity of the event.
pub fn LogRecord::level(self : LogRecord) -> @logging.Level {
  self.level
}

///|
/// The category of the event, or `None` when it has no category.
pub fn LogRecord::category(self : LogRecord) -> String? {
  self.category
}

///|
/// The message template as the caller wrote it.
pub fn LogRecord::template(self : LogRecord) -> String {
  self.template
}

///|
/// The message text, as `LogEvent::message` gave it.
pub fn LogRecord::message(self : LogRecord) -> String {
  self.message
}

///|
/// A copy of the message segments. A change to the result, or to a JSON value
/// in it, does not change the record.
pub fn LogRecord::segments(self : LogRecord) -> Array[@logging.MessageSegment] {
  self.segments.map(segment => match segment {
    Text(_) => segment
    Value(name~, value~) => Value(name~, value=copy_json(value))
  })
}

///|
/// A copy of the properties in hole order, with each repeated name. A change to
/// the result, or to a JSON value in it, does not change the record.
pub fn LogRecord::properties(self : LogRecord) -> Array[(String, Json)] {
  self.properties.map(entry => (entry.0, copy_json(entry.1)))
}

///|
/// The `Show` text of the error at capture, or `None` when the event has no
/// error.
pub fn LogRecord::error_text(self : LogRecord) -> String? {
  self.error_text
}

///|
/// A deep copy of `value`: a JSON array or object gets new arrays and maps at each
/// level, so no other code shares them.
fn copy_json(value : Json) -> Json {
  match value {
    Array(items) => Json::array(items.map(copy_json))
    Object(fields) => {
      let copy = Map([])
      for name, field in fields {
        copy[name] = copy_json(field)
      }
      Json::object(copy)
    }
    _ => value
  }
}
