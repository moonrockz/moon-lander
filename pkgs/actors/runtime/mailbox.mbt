///|
/// The queue of one actor. Producers append at the tail. Only the runner
/// removes messages, so an index that a selective receive has passed stays
/// valid while it waits. Messages that a selective receive skips stay in the
/// queue and count against the capacity; there is no second store.
priv struct Mailbox[M] {
  queue : @deque.Deque[M]
  limit : Int?
  /// False after close or drain: no message can enter.
  mut admitting : Bool
  /// The runner waits here for an arrival or for close.
  arrivals : @cond_var.Cond
  /// Producers wait here for free space or for close.
  space : @cond_var.Cond
  /// The number of producers that wait for space now.
  mut waiting_producers : Int
}

///|
fn[M] Mailbox::new(policy : @policy.MailboxPolicy) -> Mailbox[M] {
  let limit = match policy {
    Bounded(capacity) => Some(capacity.to_int())
    Unbounded => None
  }
  {
    queue: @deque.Deque([]),
    limit,
    admitting: true,
    arrivals: @cond_var.Cond(),
    space: @cond_var.Cond(),
    waiting_producers: 0,
  }
}

///|
/// A mailbox that holds `messages` and admits no more, for the test runner.
fn[M] Mailbox::fixed(messages : Array[M], admitting~ : Bool) -> Mailbox[M] {
  {
    queue: @deque.Deque(messages),
    limit: None,
    admitting,
    arrivals: @cond_var.Cond(),
    space: @cond_var.Cond(),
    waiting_producers: 0,
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
fn[M] Mailbox::admit(self : Mailbox[M], message : M) -> @policy.Admission {
  if !self.admitting {
    Closed
  } else if self.has_space() {
    self.queue.push_back(message)
    self.arrivals.broadcast()
    Accepted
  } else {
    Full
  }
}

///|
/// Wait for space, then admit. A cancellation while the producer waits leaves
/// no message, and the condition variable removes the waiter.
async fn[M] Mailbox::put(
  self : Mailbox[M],
  address : ActorAddress,
  message : M,
) -> Unit raise ActorError {
  for ;; {
    match self.admit(message) {
      Accepted => return
      Closed => fail_unless_cancelled(Closed(address))
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
/// Reject later admission, remove the queued messages and wake all waiters.
/// The result is the removed messages, oldest first.
fn[M] Mailbox::close(self : Mailbox[M]) -> Array[M] {
  self.admitting = false
  let pending = self.queue.iter().collect()
  self.queue.clear()
  self.arrivals.broadcast()
  self.space.broadcast()
  pending
}

///|
/// Remove and give the queued message at `index`.
fn[M] Mailbox::take_at(self : Mailbox[M], index : Int) -> M {
  let message = self.queue.remove(index)
  if self.waiting_producers > 0 {
    self.space.broadcast()
  }
  message
}
