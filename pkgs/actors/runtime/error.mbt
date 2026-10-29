///|
/// A fault of an actor operation.
pub suberror ActorError {
  /// The scope has ended. It cannot start another actor.
  ScopeClosed
  /// The actor's mailbox no longer admits messages.
  Closed(ActorAddress)
  /// The wait did not end within the time limit.
  TimedOut(@lander_core.TimeLimit)
  /// The actor failed with `cause` before the operation completed.
  ActorFailed(ActorAddress, Error)
  /// The actor was cancelled before it gave a result.
  ActorCancelled(ActorAddress)
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
