///|
/// One log event. Code outside this package reads the fields, but only the level
/// methods of `Logger` and the combinators of this package make events.
pub struct LogEvent {
  /// The severity of the event.
  level : Level
  /// The name of the part of the application that wrote the event, for example
  /// `morphir.build`, or `None` when no category wrapper set one.
  category : String?
  /// The message template as the caller wrote it, for example
  /// `Loaded {Count} files from {Path}`.
  template : String
  /// The values of the template holes as structured data, in hole order.
  properties : Array[(String, Json)]
  /// The error that the caller gave with the event, if any.
  error : Error?
}

///|
/// The value of the property `name`, or `None` when the event has no such property.
/// When the name occurs more than one time, the first value is the result.
pub fn LogEvent::property(self : LogEvent, name : String) -> Json? {
  for entry in self.properties {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}
