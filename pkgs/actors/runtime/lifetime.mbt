///|
/// How an actor ended.
priv enum Outcome {
  /// The receive gave its result.
  Completed
  /// The receive found the mailbox closed and had no `on_closed`.
  EndedClosed
  /// The actor raised this error.
  Failed(Error)
  /// The actor was cancelled.
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
}

///|
fn Lifetime::new(close_mailbox : () -> Unit) -> Lifetime {
  {
    address: ActorAddress::next(),
    outcome: None,
    ended: @cond_var.Cond(),
    watchers: Map([]),
    last_watcher: 0,
    close_mailbox,
  }
}

///|
/// Call `notify` when the actor ends, or now when it has already ended. The
/// result is the key for `unwatch`.
fn Lifetime::watch(self : Lifetime, notify : (Outcome) -> Unit) -> Int {
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
/// Record the outcome once: close the mailbox, then wake every watcher and
/// joiner.
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
}

///|
/// Run `body` as the actor's task and record how it ends. `body` gives true
/// when the receive gave its result. A cancellation is not an error, so the
/// `defer` records it.
async fn Lifetime::run(self : Lifetime, body : async () -> Bool) -> Unit {
  let mut outcome = Cancelled
  defer self.finish(outcome)
  let result : Result[Bool, Error] = try Ok(body()) catch { error => Err(error) }
  match result {
    Ok(true) => outcome = Completed
    Ok(false) => outcome = EndedClosed
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
