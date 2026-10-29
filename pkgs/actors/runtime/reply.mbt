///|
/// The result of a reply.
pub(all) enum ReplyOutcome {
  /// The waiting caller gets the value.
  Delivered
  /// No caller waits: the request already has a reply, timed out, or the
  /// caller was cancelled.
  Expired
} derive(Eq, Debug)

///|
pub extend ReplyOutcome with Eq::{equal, not_equal}

///|
pub extend ReplyOutcome with @debug.Debug::{to_repr}

///|
/// How long an ask waits for admission and the reply together.
pub(all) enum WaitPolicy {
  /// At most this long, from the start of the ask.
  Within(@lander_core.TimeLimit)
  /// Until the reply, or until the target ends. There is no deadline.
  UntilStopped
} derive(Eq, Debug)

///|
pub extend WaitPolicy with Eq::{equal, not_equal}

///|
pub extend WaitPolicy with @debug.Debug::{to_repr}

///|
/// The default wait of an ask: within 30 seconds.
pub fn WaitPolicy::default() -> WaitPolicy {
  Within(@lander_core.TimeLimit::seconds(30)) catch {
    _ => abort("30 seconds is a valid time limit")
  }
}

///|
priv enum ReplyState[R] {
  Waiting
  Answered(R)
  /// Close discarded the request before processing.
  Discarded
  /// The target ended with this outcome before a reply.
  Ended(ActorEnd)
  Expired
}

///|
/// A one-shot destination for the response to one request.
pub struct Reply[R] {
  priv mut state : ReplyState[R]
  priv changed : @cond_var.Cond
}

///|
fn[R] Reply::new() -> Reply[R] {
  { state: Waiting, changed: @cond_var.Cond() }
}

///|
/// Give `value` to the waiting caller. Only the first reply is delivered. The
/// call does not wait, and a late reply does not fail the actor.
pub fn[R] Reply::send(self : Reply[R], value : R) -> ReplyOutcome {
  guard self.state is Waiting else { Expired }
  self.state = Answered(value)
  self.changed.broadcast()
  Delivered
}

///|
/// End a waiting request with `state`, unless it already has an end.
fn[R] Reply::end_with(self : Reply[R], state : ReplyState[R]) -> Unit {
  if self.state is Waiting {
    self.state = state
    self.changed.broadcast()
  }
}

///|
/// Send the message that `build` makes with a fresh reply destination through
/// `admit`, and wait for the reply. One wait policy covers admission and the
/// reply. `life` is the target's termination signal, when it has one. Give
/// `None` when the time limit ends first.
async fn[M, R] ask_through(
  build : (Reply[R]) -> M,
  timeout : WaitPolicy,
  admit : async (M, (() -> Unit)?) -> Unit,
  life : Lifetime?,
  closed : ActorError,
) -> R? {
  let reply : Reply[R] = Reply::new()
  let key = match life {
    Some(life) => life.watch(end => reply.end_with(Ended(end)))
    None => 0
  }
  defer {
    if life is Some(life) {
      life.unwatch(key)
    }
    reply.end_with(Expired)
  }
  // A request that close discards wakes at once. When the actor fails, the
  // discarded request reports the failure.
  let discard = () => {
    match life {
      Some({ ending: Some(Failed(error)), .. }) => reply.end_with(Ended(Failed(error)))
      _ => reply.end_with(Discarded)
    }
  }
  let wait = async fn() -> R {
    // A closed mailbox does not end the ask at once. When the actor has
    // ended, its watcher has already recorded the outcome in `reply`, and a
    // failure must reach the caller with its cause, not as `Closed`.
    let admitted = try {
      admit(build(reply), Some(discard))
      true
    } catch {
      Closed(_) | DestinationClosed => false
      other => raise other
    }
    for ;; {
      match reply.state {
        Answered(value) => break value
        Ended(Failed(error)) =>
          match life {
            Some(life) => fail_unless_cancelled(ActorFailed(life.address, error))
            None => fail_unless_cancelled(closed)
          }
        Ended(_) | Discarded | Expired => fail_unless_cancelled(closed)
        Waiting if admitted => reply.changed.wait()
        Waiting => fail_unless_cancelled(closed)
      }
    }
  }
  match timeout {
    Within(limit) => @aio.with_timeout_opt(limit.to_millis(), wait)
    UntilStopped => Some(wait())
  }
}

///|
/// The answer of an ask, or `TimedOut` when the wait policy ended first.
fn[R] answer_or_timeout(answer : R?, timeout : WaitPolicy) -> R raise ActorError {
  match (answer, timeout) {
    (Some(value), _) => value
    (None, Within(limit)) => raise TimedOut(limit)
    (None, UntilStopped) => abort("an indefinite ask has no time limit")
  }
}

///|
/// Send the message that `build` makes with a fresh reply destination and wait
/// for the reply. One wait policy, 30 seconds by default, covers admission and
/// the reply. When the actor ends first, also while the ask waits for
/// admission, raise `Closed`, or `ActorFailed` with the actor's error. A
/// request that close discards fails at once. Cancelling the caller does not
/// undo an admitted request or cancel the actor.
pub async fn[M, R] ActorRef::ask(
  self : ActorRef[M],
  build : (Reply[R]) -> M,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> R {
  answer_or_timeout(self.try_ask(build, timeout~), timeout)
}

///|
/// Like `ask`, but give `None` when the time limit ends first. Closure and
/// failure stay typed errors.
pub async fn[M, R] ActorRef::try_ask(
  self : ActorRef[M],
  build : (Reply[R]) -> M,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> R? {
  ask_through(
    build,
    timeout,
    (message, discard) => {
      self.mailbox.put(self.life.address, message, discard?=discard)
    },
    Some(self.life),
    Closed(self.life.address),
  )
}

///|
/// Ask the actor for a reply of type `T`. See `ActorRef::ask`.
pub async fn[M, R, T] Actor::ask(
  self : Actor[M, R],
  build : (Reply[T]) -> M,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> T {
  self.target.ask(build, timeout~)
}

///|
/// Ask the actor, or give `None` on timeout. See `ActorRef::try_ask`.
pub async fn[M, R, T] Actor::try_ask(
  self : Actor[M, R],
  build : (Reply[T]) -> M,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> T? {
  self.target.try_ask(build, timeout~)
}
