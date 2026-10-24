///|
/// One handler failure in a publish.
pub(all) struct PublishFailure {
  /// The 1-based position of the handler in the topic, in add order.
  position : Int32
  /// The error that the handler raised, unchanged.
  error : Error
}

///|
/// A mediator-level failure. The core raises no error of its own for a send:
/// a missing handler is a compile error, and there is no lookup and no I/O.
/// Application errors from a send pass through as themselves. A publish
/// collects the errors of its handlers into one `PublishFailed`.
pub(all) suberror MediatorError {
  /// A handler or a middleware refuses the request or the event, for example
  /// after validation or authorization. The reason must not hold request
  /// values, because a request can hold secrets.
  Rejected(reason~ : String)
  /// One or more handlers of a publish raised an error. Every handler ran.
  /// `handlers` is the number of handlers in the publish, and `failures` holds
  /// each failure in add order.
  PublishFailed(handlers~ : Int32, failures~ : Array[PublishFailure])
  /// A step did not end within its time limit. Only the timeout middleware of
  /// the async mediator raises it. `after_ms` is the limit in milliseconds.
  TimedOut(after_ms~ : Int32)
}

///|
/// Text for people that describes the failure. The text holds only the
/// reason, the counts and the handler positions, or the time limit; the core
/// never formats a request, an event or the text of a wrapped error.
pub fn MediatorError::message(self : MediatorError) -> String {
  match self {
    Rejected(reason~) => "Request rejected: \{reason}"
    PublishFailed(handlers~, failures~) => {
      let positions = failures.map(failure => failure.position.to_string())
      let label = if positions.length() == 1 { "position" } else { "positions" }
      "Publish failed: \{failures.length()} of \{handlers} handlers raised an error (\{label} \{positions.join(", ")})"
    }
    TimedOut(after_ms~) => "Request timed out after \{after_ms} ms"
  }
}
