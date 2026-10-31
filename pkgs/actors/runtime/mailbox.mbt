///|
/// The queue of one actor. Producers append at the tail. Only the runner
/// removes messages, so an index that a selective receive has passed stays
/// valid while it waits. Messages that a selective receive skips stay in the
/// queue and count against the capacity; there is no second store.
priv struct Mailbox[M] {
  queue : @deque.Deque[M]
  /// For each queued message, what to do when close discards it. An ask uses
  /// it to wake its caller at once.
  discards : @deque.Deque[(() -> Unit)?]
  limit : Int?
  /// False after close or drain: no message can enter.
  mut admitting : Bool
  /// True after the first close.
  mut closed : Bool
  /// The runner waits here for an arrival or for close.
  arrivals : @cond_var.Cond
  /// Producers wait here for free space or for close.
  space : @cond_var.Cond
  /// The number of producers that wait for space now.
  mut waiting_producers : Int
  /// Publish an undelivered event for a message, when the owner scope has a
  /// runtime event channel. `None` does no work.
  mut undelivered : ((M, Undelivered) -> Unit)?
}

///|
fn[M] Mailbox::new(policy : @policy.MailboxPolicy) -> Mailbox[M] {
  let limit = match policy {
    Bounded(capacity) => Some(capacity.to_int())
    Unbounded => None
  }
  {
    queue: @deque.Deque([]),
    discards: @deque.Deque([]),
    limit,
    admitting: true,
    closed: false,
    arrivals: @cond_var.Cond(),
    space: @cond_var.Cond(),
    waiting_producers: 0,
    undelivered: None,
  }
}

///|
/// A mailbox that holds `messages` and admits no more, for the test runner.
fn[M] Mailbox::fixed(messages : Array[M], admitting~ : Bool) -> Mailbox[M] {
  {
    queue: @deque.Deque(messages),
    discards: @deque.Deque(Array::make(messages.length(), None)),
    limit: None,
    admitting,
    closed: false,
    arrivals: @cond_var.Cond(),
    space: @cond_var.Cond(),
    waiting_producers: 0,
    undelivered: None,
  }
}

///|
fn[M] Mailbox::has_space(self : Mailbox[M]) -> Bool {
  match self.limit {
    Some(limit) => self.queue.length() < limit
    None => true
  }
}

///|
/// Append `message` when there is space. This is the admission commit point:
/// it does not suspend, so a cancellation cannot interrupt it.
fn[M] Mailbox::admit(
  self : Mailbox[M],
  message : M,
  discard : (() -> Unit)?,
) -> @policy.Admission {
  if !self.admitting {
    Closed
  } else if self.has_space() {
    self.queue.push_back(message)
    self.discards.push_back(discard)
    self.arrivals.broadcast()
    Accepted
  } else {
    Full
  }
}

///|
/// Publish that `message` was not delivered, when a channel is present.
fn[M] Mailbox::report(
  self : Mailbox[M],
  message : M,
  reason : Undelivered,
) -> Unit {
  if self.undelivered is Some(report) {
    report(message, reason)
  }
}

///|
/// Admit `message` without waiting, and report a rejection as undelivered.
fn[M] Mailbox::offer(self : Mailbox[M], message : M) -> @policy.Admission {
  let admission = self.admit(message, None)
  match admission {
    Accepted => ()
    Full => self.report(message, Full)
    Closed => self.report(message, Closed)
  }
  admission
}

///|
/// Wait for space, then admit. A cancellation while the producer waits leaves
/// no message, and the condition variable removes the waiter.
async fn[M] Mailbox::put(
  self : Mailbox[M],
  address : ActorAddress,
  message : M,
  discard? : () -> Unit,
) -> Unit raise ActorError {
  for ;; {
    match self.admit(message, discard) {
      Accepted => return
      Closed => {
        self.report(message, Closed)
        fail_unless_cancelled(ActorError::Closed(address))
      }
      Full => {
        self.waiting_producers += 1
        defer {
          self.waiting_producers -= 1
        }
        self.space.wait()
      }
    }
  }
}

///|
/// Reject later admission and wake all waiters, but keep the queued messages
/// for the runner. Drain uses it.
fn[M] Mailbox::seal(self : Mailbox[M]) -> Unit {
  self.admitting = false
  self.arrivals.broadcast()
  self.space.broadcast()
}

///|
/// Reject later admission, remove the queued messages, wake their askers and
/// all waiters. The first close gives the removed messages, oldest first;
/// later closes give `None`. The caller gets the messages, so they are not
/// reported as undelivered.
fn[M] Mailbox::close(self : Mailbox[M]) -> Array[M]? {
  let first = !self.closed
  let pending = self.clear(_ => ())
  if first {
    Some(pending)
  } else {
    None
  }
}

///|
/// Like `close`, but report each removed message as discarded, oldest first,
/// and give nothing. Stop, cancellation and failure use it.
fn[M] Mailbox::discard(self : Mailbox[M]) -> Unit {
  ignore(self.clear(message => self.report(message, Discarded)))
}

///|
/// Reject later admission, remove the queued messages and wake all waiters.
/// Call `removed` for each message, oldest first, then wake its asker.
fn[M] Mailbox::clear(self : Mailbox[M], removed : (M) -> Unit) -> Array[M] {
  self.admitting = false
  self.closed = true
  let pending = self.queue.iter().collect()
  let discards = self.discards.iter().collect()
  self.queue.clear()
  self.discards.clear()
  self.arrivals.broadcast()
  self.space.broadcast()
  for message in pending {
    removed(message)
  }
  for discard in discards {
    if discard is Some(discard) {
      discard()
    }
  }
  pending
}

///|
/// Remove and give the queued message at `index`.
fn[M] Mailbox::take_at(self : Mailbox[M], index : Int) -> M {
  let message = self.queue.remove(index)
  ignore(self.discards.remove(index))
  if self.waiting_producers > 0 {
    self.space.broadcast()
  }
  message
}
