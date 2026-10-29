///|
/// How an actor ended.
priv enum Outcome {
  Completed
  Failed(Error)
  Cancelled
}

///|
/// The part of an actor that does not depend on its message or result type.
/// Watchers are closures, so asks with different reply types share one map
/// without a cast.
priv struct Lifetime {
  address : ActorAddress
  mut outcome : Outcome?
  ended : @cond_var.Cond
  watchers : Map[Int, (Outcome) -> Unit]
  mut last_watcher : Int
  /// Close the mailbox. Set by the actor's typed part.
  close_mailbox : () -> Unit
  /// Release the name reservation.
  release : () -> Unit
}

///|
/// Call `notify` when the actor ends, or now when it has already ended. The
/// result is the key for `unwatch`.
fn Lifetime::watch(self : Lifetime, notify : (Outcome) -> Unit) -> Int {
  if self.outcome is Some(outcome) {
    notify(outcome)
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
/// Record the outcome once: close the mailbox, wake every watcher and joiner,
/// then release the name.
fn Lifetime::finish(self : Lifetime, outcome : Outcome) -> Unit {
  guard self.outcome is None else { return }
  self.outcome = Some(outcome)
  (self.close_mailbox)()
  let watchers = self.watchers.values().collect()
  self.watchers.clear()
  for notify in watchers {
    notify(outcome)
  }
  self.ended.broadcast()
  (self.release)()
}

///|
/// Run `body` as the actor's task and record how it ends. A cancellation is
/// not an error, so the `defer` records it.
async fn Lifetime::run(self : Lifetime, body : async () -> Unit) -> Unit {
  let mut outcome = Cancelled
  defer self.finish(outcome)
  let result : Result[Unit, Error] = try Ok(body()) catch { error => Err(error) }
  match result {
    Ok(_) => outcome = Completed
    Err(error) => {
      outcome = Failed(error)
      raise error
    }
  }
}

///|
/// Wait until the actor ends.
async fn Lifetime::wait_end(self : Lifetime) -> Outcome {
  for ;; {
    if self.outcome is Some(outcome) {
      return outcome
    }
    self.ended.wait()
  }
}
