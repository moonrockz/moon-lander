///|
/// A typed send capability for one actor lifetime. It cannot receive, stop or
/// join the actor. After the actor ends, sends report `Closed`; a reference
/// never moves to another actor.
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
/// actor processes the message. Raise `Closed` when the mailbox admits no
/// more messages. A cancellation before admission leaves no message; after
/// admission it cannot take the message back.
pub async fn[M] ActorRef::send(
  self : ActorRef[M],
  message : M,
) -> Unit raise ActorError {
  self.mailbox.put(self.life.address, message)
}

///|
/// Admit `message` without waiting: `Accepted`, `Full` or `Closed`.
pub fn[M] ActorRef::try_send(
  self : ActorRef[M],
  message : M,
) -> @policy.Admission {
  self.mailbox.admit(message)
}

///|
/// The number of queued messages now. Messages that a selective receive
/// skips count; the message in progress does not.
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
/// The number of queued messages now. See `ActorRef::queued_count`.
pub fn[M, R] Actor::queued_count(self : Actor[M, R]) -> Int {
  self.target.queued_count()
}

///|
/// Wait until the actor ends. Give its result, raise its original failure,
/// raise `Closed` when its receive found the mailbox closed, or raise
/// `ActorCancelled`. Cancelling this wait does not cancel the actor.
pub async fn[M, R] Actor::join(self : Actor[M, R]) -> R {
  match self.target.life.wait_end() {
    Completed =>
      match self.result.val {
        Some(value) => value
        None => abort("an actor completed without a result")
      }
    EndedClosed => raise Closed(self.address())
    Failed(error) => raise error
    Cancelled => raise ActorCancelled(self.address())
  }
}

///|
/// What the receives of a running actor can use: its own reference, the scope
/// of its children and its queue length. A context cannot take a message, so
/// it is safe to give to another task.
pub struct ActorContext[M] {
  priv target : ActorRef[M]
  priv children : Scope
}

///|
/// The actor's own reference.
pub fn[M] ActorContext::self_ref(self : ActorContext[M]) -> ActorRef[M] {
  self.target
}

///|
/// The scope of the actor's children. When the actor ends, also normally, it
/// cancels its children and waits for them to end.
pub fn[M] ActorContext::scope(self : ActorContext[M]) -> Scope {
  self.children
}

///|
/// Append `message` to the tail of the actor's own mailbox without waiting,
/// with the capacity rule of `try_send`. Use it instead of a waiting send to
/// itself, which can wait forever on a full mailbox.
pub fn[M] ActorContext::reenqueue(
  self : ActorContext[M],
  message : M,
) -> @policy.Admission {
  self.target.try_send(message)
}

///|
/// The number of queued messages now. See `ActorRef::queued_count`.
pub fn[M] ActorContext::queued_count(self : ActorContext[M]) -> Int {
  self.target.queued_count()
}

///|
/// Make the mailbox and lifetime of a new actor.
fn[M] Scope::new_ref(
  self : Scope,
  mailbox : @policy.MailboxPolicy,
) -> ActorRef[M] raise ActorError {
  let mailbox = Mailbox::new(mailbox)
  { mailbox, life: self.begin(() => ignore(mailbox.close())) }
}

///|
/// Start the task of an actor that runs the receive that `make` gives. With
/// `children`, the actor gets a child scope that ends before the actor.
fn[M, R] Scope::run_actor(
  self : Scope,
  mailbox : @policy.MailboxPolicy,
  children~ : Bool,
  make : (ActorContext[M]) -> Receive[M, R],
) -> Actor[M, R] raise ActorError {
  let target = self.new_ref(mailbox)
  let result = Ref(None)
  let run = async fn(children : Scope) -> Bool {
    let receive = make({ target, children })
    let runner = Runner::new(target.mailbox, live=true, expire=false)
    let end = runner.run(
      receive.build(value => {
        result.val = Some(value)
        Done
      }),
    )
    end is Finished
  }
  (self.spawn_task)(() => target.life.run(() => {
    if children {
      scope(run)
    } else {
      run({ spawn_task: _ => (), open: false })
    }
  }))
  { target, result }
}

///|
/// Start an actor with state `initial`. For each message, `handler` gives the
/// next state or `Stop`. When the mailbox closes, the actor ends normally.
/// The actor belongs to this scope. This runs `receive_loop(initial, handler)`.
pub fn[S, M] Scope::start(
  self : Scope,
  initial : S,
  handler : async (S, M) -> Next[S],
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
) -> Actor[M, Unit] raise ActorError {
  self.run_actor(mailbox, children=false, _ => {
    receive_loop(initial, handler).map(_ => ())
  })
}

///|
/// Start an actor that runs the receive that `make` gives with the actor's
/// context. The actor ends with the result of that receive. Actors that start
/// in the context's scope belong to this actor and end before it.
pub fn[M, R] Scope::spawn(
  self : Scope,
  make : (ActorContext[M]) -> Receive[M, R],
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
) -> Actor[M, R] raise ActorError {
  self.run_actor(mailbox, children=true, make)
}
