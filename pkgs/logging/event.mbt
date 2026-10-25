///|
/// One immutable log event. Code outside this package reads the fields and the
/// properties, but only the level methods of `Logger` and the combinators of this
/// package make events.
pub struct LogEvent {
  /// The severity of the event.
  level : Level
  /// The name of the part of the application that wrote the event, for example
  /// `morphir.build`, or `None` when no category wrapper set one.
  category : String?
  /// The message template as the caller wrote it, for example
  /// `Loaded {Count} files from {Path}`.
  template : String
  /// The values of the template holes, in hole order. No other code holds these
  /// arrays and maps: `bind_properties` copies the arguments, and each reader gets
  /// a copy, so the event cannot change after it is made.
  priv props : Array[(String, Json)]
  /// The error that the caller gave with the event, if any.
  error : Error?
}

///|
/// The values of the template holes as structured data, in hole order. The result
/// is a copy: a change to it, or to a JSON array or object in it, does not change
/// the event.
pub fn LogEvent::properties(self : LogEvent) -> Array[(String, Json)] {
  self.props.map(entry => (entry.0, copy_json(entry.1)))
}

///|
/// A copy of the value of the property `name`, or `None` when the event has no
/// such property. When the name occurs more than one time, the first value is the
/// result.
pub fn LogEvent::property(self : LogEvent, name : String) -> Json? {
  self.find(name).map(copy_json)
}

///|
/// The first value of the property `name`, without a copy, for code in this
/// package that only reads it.
fn LogEvent::find(self : LogEvent, name : String) -> Json? {
  for entry in self.props {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
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
