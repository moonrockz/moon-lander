///|
/// The queue of one actor. Producers append at the tail. Only the consumer
/// removes messages, so an index that a scan has passed stays valid while the
/// scan waits. Messages that a scan skips stay in the queue and count against
/// the capacity; there is no second store.
priv struct Mailbox[M] {
  queue : @deque.Deque[M]
  limit : Int?
  mut open : Bool
  /// The consumer waits here for an arrival or for close.
  arrivals : @cond_var.Cond
  /// Producers wait here for free space or for close.
  space : @cond_var.Cond
  /// True while a receive or a scan waits. A second one is an ownership error.
  mut receiving : Bool
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
    open: true,
    arrivals: @cond_var.Cond(),
    space: @cond_var.Cond(),
    receiving: false,
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
  if !self.open {
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
      Full => self.space.wait()
    }
  }
}

///|
/// Reject later admission, discard the queue and wake all waiters.
fn[M] Mailbox::close(self : Mailbox[M]) -> Unit {
  self.open = false
  self.queue.clear()
  self.arrivals.broadcast()
  self.space.broadcast()
}

///|
/// Remove and give the queued message at `index`.
fn[M] Mailbox::take_at(self : Mailbox[M], index : Int) -> M {
  let message = self.queue.remove(index)
  self.space.broadcast()
  message
}

///|
/// Give the oldest message for which `select` gives a value, and remove only
/// that message. Wait for arrivals until one matches. A pending scan continues
/// from the first message that it has not tested. When `select` raises, the
/// message stays in the queue.
async fn[M, T] Mailbox::scan(
  self : Mailbox[M],
  address : ActorAddress,
  select : (M) -> T? raise,
) -> T {
  guard !self.receiving else { raise NotOwner(address) }
  self.receiving = true
  defer {
    self.receiving = false
  }
  let mut next = 0
  for ;; {
    while next < self.queue.length() {
      if select(self.queue.at(next)) is Some(selected) {
        ignore(self.take_at(next))
        return selected
      }
      next += 1
    }
    guard self.open else { fail_unless_cancelled(Closed(address)) }
    self.arrivals.wait()
  }
}

///|
/// Give the oldest message, or wait for one.
async fn[M] Mailbox::take(self : Mailbox[M], address : ActorAddress) -> M {
  self.scan(address, message => Some(message))
}
