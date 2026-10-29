///|
/// One subscription of a topic.
priv struct Subscriber[M] {
  id : Int
  subject : Subject[M]
  /// Remove the subscription's exit hook from its scope.
  release : () -> Unit
}

///|
/// A typed event channel. `publish` sends each event to the destinations
/// that are subscribed at that moment, in subscription order, and waits only
/// for their admission. It does not wait for handlers. This differs from a
/// mediator topic, which calls and awaits its handlers.
pub struct Topic[M] {
  priv mut entries : Array[Subscriber[M]]
  priv mut last_id : Int
  priv mut open : Bool
}

///|
/// A topic with no subscribers.
pub fn[M] Topic::new() -> Topic[M] {
  { entries: [], last_id: 0, open: true }
}

///|
/// The number of subscriptions now.
pub fn[M] Topic::subscriber_count(self : Topic[M]) -> Int {
  self.entries.length()
}

///|
fn[M] Topic::remove(self : Topic[M], id : Int) -> Unit {
  for entry in self.entries {
    if entry.id == id {
      (entry.release)()
    }
  }
  self.entries = self.entries.filter(entry => entry.id != id)
}

///|
/// The handle of one subscription. `unsubscribe` ends it; the end of its
/// owner scope also ends it.
pub struct Subscription {
  priv cancel : () -> Unit
}

///|
/// End the subscription. Later publications do not include it; a publication
/// already in progress can still deliver to it. A second call does nothing.
pub fn Subscription::unsubscribe(self : Subscription) -> Unit {
  (self.cancel)()
}

///|
/// Subscribe `subject` to `topic` for the lifetime of this scope. Raise
/// `ScopeClosed` for an ended scope and `TopicClosed` for a closed topic.
pub fn[M] Scope::subscribe(
  self : Scope,
  topic : Topic[M],
  subject : Subject[M],
) -> Subscription raise ActorError {
  guard self.open else { raise ScopeClosed }
  guard topic.open else { raise TopicClosed }
  topic.last_id += 1
  let id = topic.last_id
  let cancel = () => topic.remove(id)
  let release = self.on_exit(cancel)
  topic.entries.push({ id, subject, release })
  { cancel, }
}

///|
/// Send `event` to each destination of the current subscriber snapshot, in
/// subscription order, and wait for each admission. A full destination makes
/// the publication wait. A destination that reports closed is removed and
/// the publication goes on. When the caller is cancelled, or a custom
/// destination raises, earlier admissions stay and later destinations are not
/// called. Raise `TopicClosed` after `close`.
pub async fn[M] Topic::publish(self : Topic[M], event : M) -> Unit {
  guard self.open else { raise TopicClosed }
  let snapshot = self.entries.copy()
  for entry in snapshot {
    entry.subject.send(event) catch {
      Closed(_) | DestinationClosed => self.remove(entry.id)
      error => raise error
    }
  }
}

///|
/// Reject later publications and subscriptions and release every
/// subscription.
pub fn[M] Topic::close(self : Topic[M]) -> Unit {
  self.open = false
  for entry in self.entries {
    (entry.release)()
  }
  self.entries = []
}
