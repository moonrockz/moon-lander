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
  self.mailbox.admit(message, None)
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
/// Wait until the actor and its cleanup end. Give its result, raise its
/// original failure, raise `Closed` when its receive found the mailbox closed,
/// or raise `ActorCancelled`. A cleanup failure is raised as `CleanupFailed`
/// or `CleanupTimedOut`, which keep the primary failure. Several joiners get the same outcome.
/// Cancelling this wait does not cancel the actor or another joiner.
pub async fn[M, R] Actor::join(self : Actor[M, R]) -> R {
  match self.target.life.wait_end() {
    Completed =>
      match self.result.val {
        Some(value) => value
        None => abort("an actor completed without a result")
      }
    MailboxClosed => raise Closed(self.address())
    Failed(error) => raise error
    Cancelled => raise ActorCancelled(self.address())
  }
}

///|
/// The lifecycle snapshot now. It is a value, not a live view.
pub fn[M, R] Actor::status(self : Actor[M, R]) -> ActorStatus {
  self.target.life.status()
}

///|
/// Reject new messages, remove the queued messages and give them, oldest
/// first, as one immutable snapshot. Blocked producers wake with `Closed`,
/// and asks of the removed messages fail at once. The message in progress
/// can finish and reply; `close` does not wait for it, `join` does. Only the
/// first close gives a snapshot; later closes, and a close after the actor
/// has ended, give `None`.
pub fn[M, R] Actor::close(self : Actor[M, R]) -> Pending[M]? {
  let life = self.target.life
  guard life.outcome is None else { return None }
  life.closing = true
  self.target.mailbox.close().map(messages => { messages, })
}

///|
/// Reject new messages, let the actor process the queued ones, and wait
/// until it and its cleanup end. Raise like `join` when it fails or is
/// cancelled. Cancelling this wait does not cancel the actor and does not
/// open the mailbox again. A receive that never takes the queued messages
/// keeps the actor live, so give the wait a time limit in that case.
pub async fn[M, R] Actor::drain(self : Actor[M, R]) -> Unit {
  let life = self.target.life
  if life.outcome is None {
    life.closing = true
    self.target.mailbox.seal()
  }
  match life.wait_end() {
    Completed | MailboxClosed => ()
    Failed(error) => raise error
    Cancelled => raise ActorCancelled(self.address())
  }
}

///|
/// Remove the queued messages and request cancellation of the actor task.
/// Asks of the removed messages and the message in progress fail. Work in
/// progress stops at its next cancellation point: there is no hard
/// preemption. The cleanup still runs once.
pub fn[M, R] Actor::cancel(self : Actor[M, R]) -> Unit {
  let life = self.target.life
  guard life.outcome is None else { return }
  life.closing = true
  life.cancel_requested = true
  ignore(self.target.mailbox.close())
  (life.cancel_task)()
}

///|
/// The queued messages that `close` removed, oldest first.
pub struct Pending[M] {
  priv messages : Array[M]
}

///|
/// The removed messages, oldest first, as a new array.
pub fn[M] Pending::messages(self : Pending[M]) -> Array[M] {
  self.messages.copy()
}

///|
/// The number of removed messages.
pub fn[M] Pending::length(self : Pending[M]) -> Int {
  self.messages.length()
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
/// The default cleanup time limit: five seconds.
fn default_cleanup_limit() -> @lander_core.TimeLimit {
  @lander_core.TimeLimit::seconds(5) catch {
    _ => abort("5 seconds is a valid time limit")
  }
}

///|
/// Make the mailbox and lifetime of a new actor.
fn[M] Scope::new_ref(
  self : Scope,
  mailbox : @policy.MailboxPolicy,
  name : @policy.ActorName?,
) -> ActorRef[M] raise ActorError {
  let mailbox = Mailbox::new(mailbox)
  { mailbox, life: self.begin(name, () => ignore(mailbox.close())) }
}

///|
/// Start the task of an actor. `init` runs first in the task; then the actor
/// runs the receive that `make` gives. With `children`, the actor gets a child
/// scope that ends before the actor.
fn[M, R] Scope::run_actor(
  self : Scope,
  target : ActorRef[M],
  cleanup : Cleanup,
  children~ : Bool,
  init~ : async () -> Unit = () => (),
  on_start_failure~ : (Error) -> Unit = _ => (),
  make : (ActorContext[M]) -> Receive[M, R] raise,
) -> Actor[M, R] {
  let result = Ref(None)
  let run = async fn(children : Scope) -> BodyEnd {
    init() catch {
      error => return StartFailed(error)
    }
    // Processing ends here, inside the child scope: admission closes and asks
    // wake before the children are cancelled and their cleanup runs.
    let ran : Result[RunEnd, Error] = try {
      let receive = make({ target, children })
      let runner = Runner::new(target.mailbox, live=true, expire=false)
      Ok(
        runner.run(
          receive.build(value => {
            result.val = Some(value)
            Done
          }),
        ),
      )
    } catch {
      error => Err(error)
    }
    let end = match ran {
      Ok(end) => end
      Err(error) => {
        target.life.stop_processing(Failed(error))
        raise error
      }
    }
    let finished = end is Finished
    target.life.stop_processing(
      if target.life.cancel_requested {
        Cancelled
      } else if finished {
        Completed
      } else {
        MailboxClosed
      },
    )
    if finished {
      Result
    } else {
      ReceiveClosed
    }
  }
  let life = target.life
  life.cancel_task = (self.spawn_task)(() => {
    life.run(cleanup, on_start_failure~, () => {
      if children {
        scope(run)
      } else {
        run(Scope::closed())
      }
    })
  })
  { target, result }
}

///|
/// Start an actor with state `initial`. For each message, `handler` gives the
/// next state or `Stop`. When the mailbox closes, the actor ends normally.
/// `on_stop` runs once after processing ends, also after a failure or a
/// cancellation, with cancellation protection and the `cleanup_limit`
/// (5 seconds by default). The actor belongs to this scope. This runs
/// `receive_loop(initial, handler)`. With `name`, the scope reserves the name
/// first; a name that a live actor of this scope holds raises `NameInUse`.
pub fn[S, M] Scope::start(
  self : Scope,
  initial : S,
  handler : async (S, M) -> Next[S],
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  on_stop? : async () -> Unit,
  cleanup_limit? : @lander_core.TimeLimit = default_cleanup_limit(),
  name? : @policy.ActorName,
) -> Actor[M, Unit] raise ActorError {
  let target = self.new_ref(mailbox, name)
  let cleanup = { steps: on_stop.map(step => [step]).unwrap_or([]), limit: cleanup_limit }
  self.run_actor(target, cleanup, children=false, _ => {
    receive_loop(initial, handler).map(_ => ())
  })
}

///|
/// What an initializer of `start_with` can use: it registers cleanup for the
/// resources that it acquires.
pub struct Setup {
  priv steps : Array[async () -> Unit]
}

///|
/// Run `cleanup` once when the actor ends, also when the initializer fails
/// after this call. Register it after the acquisition that it releases.
/// Cleanup steps run in reverse order of registration.
pub fn Setup::on_stop(self : Setup, cleanup : async () -> Unit) -> Unit {
  self.steps.push(cleanup)
}

///|
/// Start an actor whose state comes from the async initializer `init`, which
/// runs in the actor task. Return the handle only after `init` ends. When
/// `init` fails or is cancelled, run the registered cleanup, then raise the
/// cause to this caller; no actor stays live and the scope does not fail.
pub async fn[S, M] Scope::start_with(
  self : Scope,
  init : async (Setup) -> S,
  handler : async (S, M) -> Next[S],
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  cleanup_limit? : @lander_core.TimeLimit = default_cleanup_limit(),
  name? : @policy.ActorName,
) -> Actor[M, Unit] {
  let target = self.new_ref(mailbox, name)
  target.life.started = false
  let setup : Setup = { steps: [] }
  let state = Ref(None)
  let ready : @aio.Queue[Error?] = @aio.Queue(kind=Unbounded)
  let actor = self.run_actor(
    target,
    { steps: setup.steps, limit: cleanup_limit },
    children=false,
    init=() => {
      state.val = Some(init(setup))
      target.life.started = true
      ignore(ready.try_put(None) catch { _ => false })
    },
    on_start_failure=error => {
      ignore(ready.try_put(Some(error)) catch { _ => false })
    },
    _ => {
      initialized_loop(state, handler)
    },
  )
  let outcome = @aio.handle_cancellation(() => ready.get())
  match outcome {
    Some(None) => actor
    Some(Some(error)) => raise error
    None => {
      // The creator was cancelled before the actor was ready: nobody can use
      // the actor, so cancel it too.
      actor.cancel()
      @aio.pause()
      raise ActorCancelled(actor.address())
    }
  }
}

///|
/// The state loop of `start_with` over the state that its initializer gave.
fn[S, M] initialized_loop(
  state : Ref[S?],
  handler : async (S, M) -> Next[S],
) -> Receive[M, Unit] {
  match state.val {
    Some(initial) => receive_loop(initial, handler).map(_ => ())
    None => abort("the initializer ended without a state")
  }
}

///|
/// Start an actor that runs the receive that `make` gives with the actor's
/// context. The actor ends with the result of that receive; an error of
/// `make` fails the actor. Actors that start in the context's scope belong to
/// this actor and end before it. `on_stop` and `cleanup_limit` work as in
/// `start`.
pub fn[M, R] Scope::spawn(
  self : Scope,
  make : (ActorContext[M]) -> Receive[M, R] raise,
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  on_stop? : async () -> Unit,
  cleanup_limit? : @lander_core.TimeLimit = default_cleanup_limit(),
  name? : @policy.ActorName,
) -> Actor[M, R] raise ActorError {
  let target = self.new_ref(mailbox, name)
  let cleanup = { steps: on_stop.map(step => [step]).unwrap_or([]), limit: cleanup_limit }
  self.run_actor(target, cleanup, children=true, make)
}
