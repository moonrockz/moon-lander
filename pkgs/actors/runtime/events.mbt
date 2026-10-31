///|
/// Why the runtime did not deliver a message to an actor.
pub enum Undelivered {
  /// A non-waiting send or `reenqueue` found the mailbox full.
  Full
  /// A send or non-waiting send found the actor closing or ended.
  Closed
  /// Stop, cancellation or failure removed the queued message.
  Discarded
} derive(Eq, Debug)

///|
pub extend Undelivered with Eq::{equal, not_equal}

///|
pub extend Undelivered with @debug.Debug::{to_repr}

///|
/// A runtime observation of an actor lifetime or of a message that the
/// runtime did not deliver.
pub enum ActorEvent {
  /// The actor can receive messages, after initialization.
  Started(ActorAddress)
  /// Processing and cleanup are complete. The end value matches `status()`.
  Ended(ActorAddress, ActorEnd)
  /// The target actor did not get a message. The payload is present only when
  /// the actor's payload policy selects one.
  Undelivered(ActorAddress, Undelivered, payload~ : @ion.Ion?)
} derive(Debug)

///|
pub extend ActorEvent with @debug.Debug::{to_repr}

///|
pub fn ActorEvent::to_string(self : ActorEvent) -> String {
  match self {
    Started(address) => "Started(\{address.to_string()})"
    Ended(address, end) => {
      let ending = match end {
        Completed => "Completed"
        MailboxClosed => "MailboxClosed"
        Failed(_) => "Failed"
        Cancelled => "Cancelled"
      }
      "Ended(\{address.to_string()}, \{ending})"
    }
    Undelivered(address, reason, payload~) => {
      let why = match reason {
        Full => "Full"
        Closed => "Closed"
        Discarded => "Discarded"
      }
      let with_payload = if payload is Some(_) { ", payload" } else { "" }
      "Undelivered(\{address.to_string()}, \{why}\{with_payload})"
    }
  }
}

///|
/// One subscription of a runtime event channel.
priv struct EventSubscriber {
  id : Int
  subject : Subject[ActorEvent]
  /// Remove the subscription's exit hook from its scope.
  release : () -> Unit
  /// Events dropped for this subscriber because its destination was full.
  dropped : Ref[Int]
}

///|
/// An opt-in channel for runtime actor events. Only the runtime publishes.
/// Application code has no publish operation.
pub struct RuntimeEvents {
  priv mut entries : Array[EventSubscriber]
  priv mut last_id : Int
  priv mut open : Bool
}

///|
/// A channel with no subscribers.
pub fn RuntimeEvents::new() -> RuntimeEvents {
  { entries: [], last_id: 0, open: true }
}

///|
/// The number of subscriptions now.
pub fn RuntimeEvents::subscriber_count(self : RuntimeEvents) -> Int {
  self.entries.length()
}

///|
fn RuntimeEvents::remove(self : RuntimeEvents, id : Int) -> Unit {
  for entry in self.entries {
    if entry.id == id {
      (entry.release)()
    }
  }
  self.entries = self.entries.filter(entry => entry.id != id)
}

///|
/// The handle of one runtime event subscription. `unsubscribe` ends it; the
/// end of its owner scope also ends it. `dropped_count` is how many events
/// this subscription missed because its destination was full.
pub struct EventSubscription {
  priv cancel : () -> Unit
  priv dropped : Ref[Int]
}

///|
/// End the subscription. Later publications do not include it; a publication
/// already in progress can still deliver to it. A second call does nothing.
pub fn EventSubscription::unsubscribe(self : EventSubscription) -> Unit {
  (self.cancel)()
}

///|
/// How many events this subscription dropped because its destination was full.
/// It is a snapshot, not a live view.
pub fn EventSubscription::dropped_count(self : EventSubscription) -> Int {
  self.dropped.val
}

///|
/// Subscribe `subject` to this channel for the lifetime of `owner`. Raise
/// `ScopeClosed` for an ended scope and `TopicClosed` for a closed channel.
pub fn RuntimeEvents::subscribe(
  self : RuntimeEvents,
  owner : Scope,
  subject : Subject[ActorEvent],
) -> EventSubscription raise ActorError {
  guard owner.open else { raise ScopeClosed }
  guard self.open else { raise TopicClosed }
  self.last_id += 1
  let id = self.last_id
  let dropped = Ref(0)
  let cancel = () => self.remove(id)
  let release = owner.on_exit(cancel)
  self.entries.push({ id, subject, release, dropped })
  { cancel, dropped }
}

///|
/// Reject later subscriptions, end every current subscription and stop all
/// later publication. A closed channel does not fail the scopes that use it.
pub fn RuntimeEvents::close(self : RuntimeEvents) -> Unit {
  self.open = false
  for entry in self.entries {
    (entry.release)()
  }
  self.entries = []
}

///|
/// Deliver `event` to each current subscriber with non-waiting admission, in
/// subscription order. On `Full`, drop for that subscriber and count. On
/// `Closed`, remove the subscription. Never wait and never publish an event
/// about this delivery.
fn RuntimeEvents::publish(self : RuntimeEvents, event : ActorEvent) -> Unit {
  guard self.open else { return }
  let snapshot = self.entries.copy()
  for entry in snapshot {
    self.deliver(entry, event)
  }
}

///|
/// Offer `event` to one subscriber without a runtime report of its own.
fn RuntimeEvents::deliver(
  self : RuntimeEvents,
  entry : EventSubscriber,
  event : ActorEvent,
) -> Unit {
  match entry.subject.try_send_quietly(event) {
    Accepted => ()
    Full => entry.dropped.val += 1
    Closed => self.remove(entry.id)
  }
}

///|
/// Publish that `address` did not get `message`. Encode the payload only when
/// the channel has a subscription, once; each subscriber but the last gets a
/// deep copy, so no subscriber sees a change that another makes.
fn[M] RuntimeEvents::publish_undelivered(
  self : RuntimeEvents,
  address : ActorAddress,
  reason : Undelivered,
  payload : (M) -> @ion.Ion?,
  message : M,
) -> Unit {
  guard self.open && !self.entries.is_empty() else { return }
  let encoded = payload(message)
  let snapshot = self.entries.copy()
  let last = snapshot.length() - 1
  for index, entry in snapshot {
    let payload = if index == last { encoded } else { encoded.map(copy_ion) }
    self.deliver(entry, Undelivered(address, reason, payload~))
  }
}

///|
/// A deep copy of `value`: new arrays for its annotations and containers.
/// Scalars hold immutable data and are shared. It uses no recursion.
fn copy_ion(value : @ion.Ion) -> @ion.Ion {
  value.fold_up(
    scalar=scalar => scalar.with_annotations(scalar.annotations().copy()),
    container=(original, children) => {
      let rebuilt = match original.kind() {
        Struct(_) =>
          @ion.Ion::from_fields(
            children.map(child => {
              match child.0 {
                Some(name) => @ion.Field::from_token(name, child.1)
                None => abort("a struct field has a name")
              }
            }),
          )
        Sexp(_) => @ion.Ion::sexp(children.map(child => child.1))
        _ => @ion.Ion::list(children.map(child => child.1))
      }
      rebuilt.with_annotations(original.annotations().copy())
    },
  )
}

///|
/// Publish when this channel is present. A missing channel does nothing.
fn publish_event(events : RuntimeEvents?, event : ActorEvent) -> Unit {
  match events {
    Some(channel) => channel.publish(event)
    None => ()
  }
}
