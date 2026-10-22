///|
/// A mediator-level failure that a handler or a middleware raises. The core
/// raises no error of its own: a missing handler is a compile error, and there
/// is no lookup and no I/O. Application errors pass through as themselves.
pub(all) suberror MediatorError {
  /// A handler or a middleware refuses the request or the event, for example
  /// after validation or authorization. The reason must not hold request
  /// values, because a request can hold secrets.
  Rejected(reason~ : String)
}

///|
/// Text for people that describes the failure. The text holds only the
/// reason; the core never formats a request.
pub fn MediatorError::message(self : MediatorError) -> String {
  match self {
    Rejected(reason~) => "Request rejected: \{reason}"
  }
}
