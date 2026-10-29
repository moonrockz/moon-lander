///|
/// A fault of an actor operation.
pub suberror ActorError {
  /// The scope has ended. It cannot start another actor.
  ScopeClosed
  /// Another live actor of this scope holds the name. The initializer of the
  /// new actor did not run.
  NameInUse(@policy.ActorName)
  /// The actor's mailbox no longer admits messages.
  Closed(ActorAddress)
  /// The wait did not end within the time limit.
  TimedOut(@lander_core.TimeLimit)
  /// The actor failed with `cause` before the operation completed.
  ActorFailed(ActorAddress, Error)
  /// The actor was cancelled before it gave a result.
  ActorCancelled(ActorAddress)
  /// The topic is closed. It accepts no publication or subscription.
  TopicClosed
  /// A destination that is not an actor admits no more messages.
  DestinationClosed
  /// A cleanup step raised `cleanup`; `primary` is the actor's own failure.
  CleanupFailed(primary~ : Error?, cleanup~ : Error)
  /// The cleanup did not end within `limit`; `primary` is the actor's own
  /// failure.
  CleanupTimedOut(primary~ : Error?, limit~ : @lander_core.TimeLimit)
} derive(Debug)

///|
pub extend ActorError with @debug.Debug::{to_repr}

///|
/// Raise `error`, unless the caller is being cancelled. A waiter can wake
/// because a peer ended during scope exit, just before its own cancellation
/// takes effect. Reporting `Closed` there would fail the owner scope with an
/// error that only the teardown caused, so `pause` raises the cancellation.
async fn[T] fail_unless_cancelled(error : ActorError) -> T raise ActorError {
  if @aio.is_being_cancelled() {
    @aio.pause()
  }
  raise error
}
