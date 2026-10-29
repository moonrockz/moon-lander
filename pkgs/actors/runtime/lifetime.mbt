///|
/// How an actor ended.
pub enum ActorEnd {
  /// The receive gave its result.
  Completed
  /// The receive found the mailbox closed and had no `on_closed`.
  MailboxClosed
  /// The actor raised this error, or its startup failed with it.
  Failed(Error)
  /// The actor was cancelled.
  Cancelled
} derive(Debug)

///|
pub extend ActorEnd with @debug.Debug::{to_repr}

///|
/// An immutable snapshot of an actor's lifecycle.
pub enum ActorStatus {
  /// The actor admits and processes messages.
  Running
  /// The actor admits no more messages. It can still process admitted work
  /// or run its cleanup.
  Closing
  /// The actor and its cleanup have ended.
  Ended(ActorEnd)
} derive(Debug)

///|
pub extend ActorStatus with @debug.Debug::{to_repr}

///|
/// How the body of an actor task ended.
priv enum BodyEnd {
  /// The receive gave its result.
  Result
  /// The receive found the mailbox closed.
  ReceiveClosed
  /// The initializer failed. The creator gets the error; the scope does not.
  StartFailed(Error)
}

///|
/// The part of an actor that does not depend on its message or result type.
/// Watchers are closures, so asks with different reply types share one map
/// without a cast.
priv struct Lifetime {
  address : ActorAddress
  /// How the actor ends, set when processing ends and before cleanup.
  mut ending : ActorEnd?
  /// How the actor ended, set after cleanup.
  mut outcome : ActorEnd?
  /// True after close, drain or cancel, or when processing has ended.
  mut closing : Bool
  ended : @cond_var.Cond
  watchers : Map[Int, (ActorEnd) -> Unit]
  mut last_watcher : Int
  /// Close the mailbox. Set by the actor's typed part.
  close_mailbox : () -> Unit
  /// Cancel the actor task. Set when the task starts.
  mut cancel_task : () -> Unit
  /// True after `cancel`. The task can end before the cancellation reaches
  /// it, for example when it has not run yet; it still ends as cancelled.
  mut cancel_requested : Bool
  /// Release the name reservation of the actor, after cleanup.
  release : () -> Unit
}

///|
fn Lifetime::new(
  address : ActorAddress,
  close_mailbox : () -> Unit,
  release : () -> Unit,
) -> Lifetime {
  {
    address,
    ending: None,
    outcome: None,
    closing: false,
    ended: @cond_var.Cond(),
    watchers: Map([]),
    last_watcher: 0,
    close_mailbox,
    cancel_task: () => (),
    cancel_requested: false,
    release,
  }
}

///|
/// The lifecycle snapshot now.
fn Lifetime::status(self : Lifetime) -> ActorStatus {
  match self.outcome {
    Some(end) => Ended(end)
    None => if self.closing { Closing } else { Running }
  }
}

///|
/// Call `notify` when the actor ends, or now when it has already ended. The
/// result is the key for `unwatch`.
fn Lifetime::watch(self : Lifetime, notify : (ActorEnd) -> Unit) -> Int {
  if self.outcome is Some(outcome) {
    notify(outcome)
    // No key is stored, so `unwatch` of this key does nothing.
    return 0
  }
  self.last_watcher += 1
  self.watchers[self.last_watcher] = notify
  self.last_watcher
}

///|
fn Lifetime::unwatch(self : Lifetime, key : Int) -> Unit {
  self.watchers.remove(key)
}

///|
/// Record the outcome once, wake every watcher and joiner, then release the
/// name.
fn Lifetime::finish(self : Lifetime, outcome : ActorEnd) -> Unit {
  guard self.outcome is None else { return }
  self.closing = true
  self.outcome = Some(outcome)
  let watchers = self.watchers.values().collect()
  self.watchers.clear()
  for notify in watchers {
    notify(outcome)
  }
  self.ended.broadcast()
  (self.release)()
}

///|
/// The cleanup of one actor: functions that run once after processing ends,
/// in reverse order of registration, within one time limit.
priv struct Cleanup {
  steps : Array[async () -> Unit]
  limit : @lander_core.TimeLimit
}

///|
/// Run the cleanup steps with cancellation protection and the time limit.
/// Give the first error, or `None`.
async fn Cleanup::run(self : Cleanup, primary : Error?) -> Error? {
  guard !self.steps.is_empty() else { return None }
  let errors : Array[Error] = []
  let finished = @aio.protect_from_cancel(() => {
    @aio.with_timeout_opt(self.limit.to_millis(), () => {
      for index = self.steps.length() - 1; index >= 0; index = index - 1 {
        (self.steps[index])() catch {
          error => errors.push(error)
        }
      }
    })
  })
  match (finished, errors) {
    (None, _) => Some(CleanupTimedOut(primary~, limit=self.limit))
    (Some(_), [cleanup, ..]) => Some(CleanupFailed(primary~, cleanup~))
    (Some(_), []) => None
  }
}

///|
/// Run `body` as the actor's task: record how processing ends, close the
/// mailbox, run the cleanup once, then record the outcome. A cancellation is
/// not an error; it ends processing as cancelled. An actor failure, and a
/// cleanup failure also after cancellation, is raised and fails the owner
/// scope. A startup failure goes to `on_start_failure` instead.
async fn Lifetime::run(
  self : Lifetime,
  cleanup : Cleanup,
  body : async () -> BodyEnd,
  on_start_failure~ : (Error) -> Unit = _ => (),
) -> Unit {
  let ended : Result[BodyEnd?, Error] = try
    Ok(@aio.handle_cancellation(body))
  catch {
    error => Err(error)
  }
  let (end, primary, started) = match ended {
    Ok(Some(Result | ReceiveClosed)) if self.cancel_requested =>
      (Cancelled, None, true)
    Ok(Some(Result)) => (Completed, None, true)
    Ok(Some(ReceiveClosed)) => (MailboxClosed, None, true)
    Ok(Some(StartFailed(error))) => (Failed(error), Some(error), false)
    Ok(None) => (Cancelled, None, true)
    Err(error) => (Failed(error), Some(error), true)
  }
  self.ending = Some(end)
  self.closing = true
  (self.close_mailbox)()
  let cleanup_error = cleanup.run(primary)
  self.finish(end)
  match (started, cleanup_error, primary) {
    (false, Some(error), _) | (false, None, Some(error)) =>
      on_start_failure(error)
    (false, None, None) => ()
    (true, Some(error), _) | (true, None, Some(error)) => raise error
    (true, None, None) => ()
  }
}

///|
/// Wait until the actor and its cleanup end.
async fn Lifetime::wait_end(self : Lifetime) -> ActorEnd {
  for ;; {
    if self.outcome is Some(outcome) {
      return outcome
    }
    self.ended.wait()
  }
}
