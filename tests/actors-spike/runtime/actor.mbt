///|
/// What a state handler gives after one message.
pub(all) enum Next[S] {
  /// Process the next message with this state.
  Continue(S)
  /// End normally and discard the queued messages.
  Stop
}

///|
/// A typed send capability for one actor lifetime. It cannot receive, stop or
/// join the actor. After the actor ends, sends report `Closed`; a reference
/// never moves to a replacement actor.
pub struct ActorRef[M] {
  priv mailbox : Mailbox[M]
  priv life : Lifetime
}

///|
/// The address of the actor lifetime.
pub fn[M] ActorRef::address(self : ActorRef[M]) -> ActorAddress {
  self.life.address
}

///|
/// Wait for space and admit `message`. Return at admission, not after the
/// actor processes the message.
pub async fn[M] ActorRef::send(
  self : ActorRef[M],
  message : M,
) -> Unit raise ActorError {
  self.mailbox.put(self.life.address, message)
}

///|
/// Admit `message` without waiting.
pub fn[M] ActorRef::try_send(
  self : ActorRef[M],
  message : M,
) -> @policy.Admission {
  self.mailbox.admit(message)
}

///|
/// The number of queued messages now. A scan's skipped messages count; the
/// in-flight message does not.
pub fn[M] ActorRef::queued_count(self : ActorRef[M]) -> Int {
  self.mailbox.queue.length()
}

///|
/// The owner handle of an actor with protocol `M` and final result `R`.
pub struct Actor[M, R] {
  priv target : ActorRef[M]
  priv result : Ref[R?]
}

///|
/// A send-only reference to the actor.
pub fn[M, R] Actor::to_ref(self : Actor[M, R]) -> ActorRef[M] {
  self.target
}

///|
/// The address of the actor lifetime.
pub fn[M, R] Actor::address(self : Actor[M, R]) -> ActorAddress {
  self.target.address()
}

///|
/// Send `message` to the actor. See `ActorRef::send`.
pub async fn[M, R] Actor::send(
  self : Actor[M, R],
  message : M,
) -> Unit raise ActorError {
  self.target.send(message)
}

///|
/// Admit `message` without waiting. See `ActorRef::try_send`.
pub fn[M, R] Actor::try_send(
  self : Actor[M, R],
  message : M,
) -> @policy.Admission {
  self.target.try_send(message)
}

///|
/// Wait until the actor ends. Give its result, raise its original failure, or
/// raise `ActorCancelled`. Cancelling this wait does not cancel the actor.
pub async fn[M, R] Actor::join(self : Actor[M, R]) -> R {
  match self.target.life.wait_end() {
    Completed => self.result.val.unwrap()
    Failed(error) => raise error
    Cancelled => raise ActorCancelled(self.address())
  }
}

///|
/// True when the actor has ended.
pub fn[M, R] Actor::is_ended(self : Actor[M, R]) -> Bool {
  self.target.life.outcome is Some(_)
}

///|
fn[M] Scope::new_ref(
  self : Scope,
  mailbox : @policy.MailboxPolicy,
  name : @policy.ActorName?,
) -> ActorRef[M] raise ActorError {
  let mailbox = Mailbox::new(mailbox)
  { mailbox, life: self.begin(name, () => mailbox.close()) }
}

///|
/// Start an actor with state `initial`. For each message, `handler` gives the
/// next state or `Stop`. The actor belongs to this scope.
pub fn[S, M] Scope::start(
  self : Scope,
  initial : S,
  handler : async (S, M) -> Next[S],
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  name? : @policy.ActorName,
) -> Actor[M, Unit] raise ActorError {
  let target = self.new_ref(mailbox, name)
  (self.spawn_task)(() => target.life.run(() => {
    let mut state = initial
    for ;; {
      let message = target.mailbox.take(target.life.address) catch {
        Closed(_) => break
        error => raise error
      }
      match handler(state, message) {
        Continue(next) => state = next
        Stop => break
      }
    }
  }))
  { target, result: Ref(Some(())) }
}

///|
/// The receive side of a running actor. Only the actor body gets it.
pub struct Inbox[M] {
  priv target : ActorRef[M]
  priv children : Scope
  priv mut live : Bool
}

///|
/// Start an actor that runs `body` with its inbox. The actor ends with the
/// result of `body`. Actors that `body` starts through `Inbox::scope` belong to
/// this actor and end before it.
pub fn[M, R] Scope::spawn(
  self : Scope,
  body : async (Inbox[M]) -> R,
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  name? : @policy.ActorName,
) -> Actor[M, R] raise ActorError {
  let target = self.new_ref(mailbox, name)
  let result = Ref(None)
  (self.spawn_task)(() => target.life.run(() => scope(children => {
    let inbox = { target, children, live: true }
    defer {
      inbox.live = false
    }
    result.val = Some(body(inbox))
  })))
  { target, result }
}

///|
/// The actor's own reference.
pub fn[M] Inbox::self_ref(self : Inbox[M]) -> ActorRef[M] {
  self.target
}

///|
/// The scope that owns this actor's children.
pub fn[M] Inbox::scope(self : Inbox[M]) -> Scope {
  self.children
}

///|
fn[M] Inbox::check_owner(self : Inbox[M]) -> Unit raise ActorError {
  guard self.live else { raise NotOwner(self.target.address()) }
}

///|
/// Take the oldest message, or wait for one. Raise `Closed` when the mailbox
/// is closed and empty.
pub async fn[M] Inbox::receive(self : Inbox[M]) -> M raise {
  self.check_owner()
  self.target.mailbox.take(self.target.address())
}

///|
/// Take the oldest message that `select` chooses. Messages that it skips keep
/// their order. With `timeout`, raise `TimedOut` and leave the mailbox as it
/// was when no message matches in time.
pub async fn[M, T] Inbox::scan(
  self : Inbox[M],
  select : (M) -> T? raise?,
  timeout? : @lander_core.TimeLimit,
) -> T raise {
  self.check_owner()
  let address = self.target.address()
  let select = lift_selector(select)
  match timeout {
    None => self.target.mailbox.scan(address, select)
    Some(limit) =>
      match
        @aio.with_timeout_opt(limit.to_millis(), () => {
          self.target.mailbox.scan(address, select)
        }) {
        Some(selected) => selected
        None => raise TimedOut(limit)
      }
  }
}

///|
/// Append `message` to this actor's own mailbox without waiting.
pub fn[M] Inbox::reenqueue(self : Inbox[M], message : M) -> @policy.Admission {
  self.target.try_send(message)
}

///|
/// The number of queued messages now.
pub fn[M] Inbox::queued_count(self : Inbox[M]) -> Int {
  self.target.queued_count()
}

///|
/// Give `select` the error effect `raise`. The pinned compiler fails to link an
/// async function that calls a `raise?` parameter, so the async code calls this
/// synchronous wrapper instead.
fn[M, T] lift_selector(select : (M) -> T? raise?) -> (M) -> T? raise {
  message => select(message)
}
