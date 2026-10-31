///|
/// A typed send-only destination: an actor, a one-shot reply, an async queue
/// or caller-supplied functions. `contramap` adapts the message type before
/// admission, with no other queue or task.
pub struct Subject[M] {
  priv admit : async (M, (() -> Unit)?) -> Unit
  priv offer : (M) -> @policy.Admission
  /// Like `offer`, but a rejection publishes no runtime event. The runtime
  /// event channel uses it, so an event delivery causes no event.
  priv offer_quietly : (M) -> @policy.Admission
  priv life : Lifetime?
  priv closed : ActorError
}

///|
/// Wait for admission of `message`. Raise `Closed`, or `DestinationClosed` for
/// a destination that is not an actor, when it admits no more messages. An
/// error of a custom send function passes unchanged.
pub async fn[M] Subject::send(self : Subject[M], message : M) -> Unit {
  (self.admit)(message, None)
}

///|
/// Admit `message` without waiting.
pub fn[M] Subject::try_send(self : Subject[M], message : M) -> @policy.Admission {
  (self.offer)(message)
}

///|
/// Admit `message` without waiting and without a runtime event on rejection.
fn[M] Subject::try_send_quietly(
  self : Subject[M],
  message : M,
) -> @policy.Admission {
  (self.offer_quietly)(message)
}

///|
/// A destination of messages of type `N` that maps each message with `f`
/// and sends it to this destination.
pub fn[M, N] Subject::contramap(self : Subject[M], f : (N) -> M) -> Subject[N] {
  {
    admit: (message, discard) => (self.admit)(f(message), discard),
    offer: message => (self.offer)(f(message)),
    offer_quietly: message => (self.offer_quietly)(f(message)),
    life: self.life,
    closed: self.closed,
  }
}

///|
/// The destination of an actor reference.
pub fn[M] ActorRef::to_subject(self : ActorRef[M]) -> Subject[M] {
  {
    admit: (message, discard) => {
      self.mailbox.put(self.life.address, message, discard?=discard)
    },
    offer: message => self.mailbox.offer(message),
    offer_quietly: message => self.mailbox.admit(message, None),
    life: Some(self.life),
    closed: Closed(self.life.address),
  }
}

///|
/// The destination of a one-shot reply. The first message is delivered;
/// later ones report closed.
pub fn[M] Subject::from_reply(reply : Reply[M]) -> Subject[M] {
  let offer : (M) -> @policy.Admission = message => {
    match reply.send(message) {
      Delivered => Accepted
      Expired => Closed
    }
  }
  {
    admit: (message, _) => {
      guard reply.send(message) is Delivered else { raise DestinationClosed }
    },
    offer,
    offer_quietly: offer,
    life: None,
    closed: DestinationClosed,
  }
}

///|
/// The destination of an async queue. A closed queue reports closed.
pub fn[M] Subject::from_queue(queue : @aio.Queue[M]) -> Subject[M] {
  let offer : (M) -> @policy.Admission = message => {
    let admitted = queue.try_put(message) catch { _ => return Closed }
    if admitted {
      Accepted
    } else {
      Full
    }
  }
  {
    admit: (message, _) => {
      queue.put(message) catch {
        _ => raise DestinationClosed
      }
    },
    offer,
    offer_quietly: offer,
    life: None,
    closed: DestinationClosed,
  }
}

///|
/// The result of a waiting send of a custom destination.
pub(all) enum SendOutcome {
  /// The destination admitted the message.
  Admitted
  /// The destination admits no more messages.
  Rejected
} derive(Eq, Debug)

///|
pub extend SendOutcome with Eq::{equal, not_equal}

///|
pub extend SendOutcome with @debug.Debug::{to_repr}

///|
/// A destination of caller-supplied functions. `send` waits for admission
/// and gives `Rejected` when the destination admits no more messages;
/// `try_send` does not wait. The runtime cannot check that the functions keep
/// the rules of a mailbox.
pub fn[M] Subject::new(
  send~ : async (M) -> SendOutcome,
  try_send~ : (M) -> @policy.Admission,
) -> Subject[M] {
  {
    admit: (message, _) => {
      guard send(message) is Admitted else { raise DestinationClosed }
    },
    offer: try_send,
    offer_quietly: try_send,
    life: None,
    closed: DestinationClosed,
  }
}

///|
/// Send the message that `build` makes with a fresh reply destination to this
/// destination and wait for the reply, with the deadline and one-shot rules
/// of `ActorRef::ask`. The ask observes the end of the target only when the
/// destination is an actor.
pub async fn[M, R] Subject::ask(
  self : Subject[M],
  build : (Reply[R]) -> M,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> R {
  answer_or_timeout(self.try_ask(build, timeout~), timeout)
}

///|
/// Like `Subject::ask`, but give `None` when the time limit ends first.
pub async fn[M, R] Subject::try_ask(
  self : Subject[M],
  build : (Reply[R]) -> M,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> R? {
  ask_through(build, timeout, self.admit, self.life, self.closed)
}
