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
priv enum ReplyState[R] {
  Waiting
  Answered(R)
  Ended(Outcome)
  Expired
}

///|
/// A one-shot destination for the response to one request.
pub struct Reply[R] {
  priv mut state : ReplyState[R]
  priv changed : @cond_var.Cond
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
/// The default time limit of an ask: 30 seconds.
fn default_ask_limit() -> @lander_core.TimeLimit {
  @lander_core.TimeLimit::seconds(30) catch {
    _ => panic()
  }
}

///|
/// Send the message that `build` makes with a fresh reply destination and wait
/// for the reply. One time limit, 30 seconds by default, covers admission and
/// the reply. When the actor ends first, also while the ask waits for
/// admission, raise `Closed`, or `ActorFailed` with the actor's error. Cancelling the caller does not undo an admitted request.
pub async fn[M, R] ActorRef::ask(
  self : ActorRef[M],
  build : (Reply[R]) -> M,
  timeout? : @lander_core.TimeLimit = default_ask_limit(),
) -> R raise {
  let reply : Reply[R] = { state: Waiting, changed: @cond_var.Cond() }
  let key = self.life.watch(outcome => {
    if reply.state is Waiting {
      reply.state = Ended(outcome)
      reply.changed.broadcast()
    }
  })
  defer {
    self.life.unwatch(key)
    if reply.state is Waiting {
      reply.state = Expired
    }
  }
  let address = self.address()
  let answer = @aio.with_timeout_opt(timeout.to_millis(), () => {
    // A closed mailbox does not end the ask at once. When the actor has
    // ended, its watcher has already recorded the outcome in `reply`, and a
    // failure must reach the caller with its cause, not as `Closed`.
    let admitted = try {
      self.send(build(reply))
      true
    } catch {
      Closed(_) => false
      other => raise other
    }
    for ;; {
      match reply.state {
        Answered(value) => break value
        Ended(Failed(error)) => fail_unless_cancelled(ActorFailed(address, error))
        Ended(_) | Expired => fail_unless_cancelled(Closed(address))
        Waiting if admitted => reply.changed.wait()
        Waiting => fail_unless_cancelled(Closed(address))
      }
    }
  })
  match answer {
    Some(value) => value
    None => raise TimedOut(timeout)
  }
}

///|
/// Ask the actor for a reply of type `T`. See `ActorRef::ask`.
pub async fn[M, R, T] Actor::ask(
  self : Actor[M, R],
  build : (Reply[T]) -> M,
  timeout? : @lander_core.TimeLimit = default_ask_limit(),
) -> T raise {
  self.target.ask(build, timeout~)
}
