///|
/// One handler failure in a publish. Only mediator constructs this record.
pub struct PublishFailure {
  /// The 1-based position of the handler in the topic, in add order.
  position : Int
  /// The error that the handler raised, unchanged.
  error : Error
}

///|
/// An immutable failure collection. Accessors do not expose its storage.
struct PublishFailures {
  items : Array[PublishFailure]
}

///|
/// Give the number of failed handlers.
pub fn PublishFailures::length(self : PublishFailures) -> Int {
  self.items.length()
}

///|
/// Give the failure at a zero-based index, or None when the index is outside
/// the collection.
pub fn PublishFailures::get(self : PublishFailures, index : Int) -> PublishFailure? {
  self.items.get(index)
}

///|
/// Give an array copy. Changes to this array do not change the collection.
pub fn PublishFailures::to_array(self : PublishFailures) -> Array[PublishFailure] {
  self.items.copy()
}

///|
/// A mediator-level failure. Callers can match cases but use the supported
/// constructors to make errors. Application errors from send pass unchanged.
pub suberror MediatorError {
  /// A handler or middleware refuses a request. The reason must not hold
  /// request values, because a request can hold secrets.
  Rejected(reason~ : String)
  /// One or more handlers failed. The count and positions come from the
  /// handler outcomes; the failure collection cannot change.
  PublishFailed(handlers~ : Int, failures~ : PublishFailures)
  /// A step did not end within the shared core time limit.
  TimedOut(after~ : @lander_core.TimeLimit)
}

///|
/// Refuse a request or event. Use a reason that holds no request values.
pub fn MediatorError::rejected(reason : String) -> MediatorError {
  Rejected(reason~)
}

///|
/// Describe a timeout with a valid shared core time limit.
pub fn MediatorError::timed_out(after : @lander_core.TimeLimit) -> MediatorError {
  TimedOut(after~)
}

///|
/// Derive a publish error from one optional error per handler in add order.
/// None is a successful handler. Empty and all-success arrays give None.
/// Failed slots derive the count and positive positions. The error retains
/// no caller-owned array, so later changes to `errors` do not change it.
pub fn MediatorError::from_publish_errors(
  errors : Array[Error?],
) -> MediatorError? {
  let failures = []
  for index, error in errors {
    if error is Some(error) {
      failures.push({ position: index + 1, error })
    }
  }
  if failures.is_empty() {
    None
  } else {
    Some(PublishFailed(handlers=errors.length(), failures={ items: failures }))
  }
}

///|
/// Text for people. It holds only the reason, counts and positions, or time
/// limit. It never formats request values, events or wrapped error text.
pub fn MediatorError::message(self : MediatorError) -> String {
  match self {
    Rejected(reason~) => "Request rejected: \{reason}"
    PublishFailed(handlers~, failures~) => {
      let positions = failures.items.map(failure => failure.position.to_string())
      let label = if positions.length() == 1 { "position" } else { "positions" }
      "Publish failed: \{failures.length()} of \{handlers} handlers raised an error (\{label} \{positions.join(", ")})"
    }
    TimedOut(after~) => "Request timed out after \{after.to_millis()} ms"
  }
}
