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
  /// False while an initializer of `start_with` runs.
  mut started : Bool
  /// Release the name reservation of the actor, after cleanup.
  release : () -> Unit
  /// The opt-in runtime event channel of the owner scope, if any.
  events : RuntimeEvents?
}

///|
fn Lifetime::new(
  address : ActorAddress,
  close_mailbox : () -> Unit,
  events : RuntimeEvents?,
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
    started: true,
    release,
    events,
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
/// Call `notify` when the actor's processing ends, before its cleanup, or now
/// when it has already ended. Asks use it: no reply can come after that. The
/// result is the key for `unwatch`.
fn Lifetime::watch(self : Lifetime, notify : (ActorEnd) -> Unit) -> Int {
  if self.ending is Some(ending) {
    notify(ending)
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
/// Record how processing ended once and wake every watcher. The mailbox
/// closes after this, so an ask that waits for space reads the end.
fn Lifetime::end_processing(self : Lifetime, ending : ActorEnd) -> Unit {
  guard self.ending is None else { return }
  self.ending = Some(ending)
  self.closing = true
  let watchers = self.watchers.values().collect()
  self.watchers.clear()
  for notify in watchers {
    notify(ending)
  }
}

///|
/// End processing with `ending`: wake the watchers, then close the mailbox.
/// Only the first call has an effect.
fn Lifetime::stop_processing(self : Lifetime, ending : ActorEnd) -> Unit {
  guard self.ending is None else { return }
  self.end_processing(ending)
  (self.close_mailbox)()
}

///|
/// Record the outcome once, after cleanup, wake every joiner, then release
/// the name.
fn Lifetime::finish(self : Lifetime, outcome : ActorEnd) -> Unit {
  guard self.outcome is None else { return }
  self.outcome = Some(outcome)
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
  // `primary` is the actor's own failure. `start_error` is what the creator
  // of an actor that never became ready gets.
  let (end, primary, start_error) = match ended {
    Ok(Some(Result | ReceiveClosed)) if self.cancel_requested =>
      (Cancelled, None, None)
    Ok(Some(Result)) => (Completed, None, None)
    Ok(Some(ReceiveClosed)) => (MailboxClosed, None, None)
    Ok(Some(StartFailed(error))) => (Failed(error), Some(error), Some(error))
    Ok(None) if !self.started =>
      (Cancelled, None, Some(ActorCancelled(self.address)))
    Ok(None) => (Cancelled, None, None)
    Err(error) => (Failed(error), Some(error), None)
  }
  self.stop_processing(end)
  let cleanup_error = cleanup.run(primary)
  // A cleanup failure is the final outcome; it keeps the primary failure.
  let outcome = match cleanup_error {
    Some(error) => Failed(error)
    None => end
  }
  self.finish(outcome)
  // A failed initializer never became ready, so it publishes no end event.
  if start_error is None {
    publish_event(self.events, Ended(self.address, outcome))
  }
  match (start_error, cleanup_error, primary) {
    (Some(_), Some(error), _) | (Some(error), None, _) =>
      on_start_failure(error)
    (None, Some(error), _) | (None, None, Some(error)) => raise error
    (None, None, None) => ()
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
