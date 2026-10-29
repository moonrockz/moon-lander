///|
/// A live runner checks the clock after this many messages taken without a
/// wait.
const BATCH_CHECK : Int = 64

///|
/// A live runner lets other tasks run when its batch has taken at least this
/// many milliseconds. A yield costs about 12 microseconds on native and at
/// least one millisecond on js (`setTimeout`), so a time slice keeps the cost
/// small for short handlers and the batch bounded for slow ones.
const BATCH_SLICE_MS : Int64 = 2L

///|
/// How a run of a receive ended.
priv enum RunEnd {
  /// The receive gave its result.
  Finished
  /// A receive had to wait, and the test runner does not wait.
  Pending
  /// A receive found the mailbox closed, with no `on_closed`.
  ReceiveClosed
}

///|
/// The result of one runner turn: the next step, or the end of the run.
priv enum Turn[M] {
  Go(Step[M])
  End(RunEnd)
}

///|
/// A frame and, for a time limit, the wait time that remains.
priv struct Entry[M] {
  frame : Frame[M]
  mut left : Int64
}

///|
/// Runs the step machine of one receive against one mailbox. The actor
/// runtime runs it live: it waits for arrivals and timers. The test runner
/// does not wait: a wait ends the run, or expires a time limit at once.
priv struct Runner[M] {
  mailbox : Mailbox[M]
  live : Bool
  /// For the test runner: a wait expires the nearest time limit.
  expire : Bool
  frames : Array[Entry[M]]
  /// The messages taken since the runner last waited or yielded.
  mut batch : Int
  /// The time at which the batch started.
  mut batch_start : Int64
}

///|
fn[M] Runner::new(mailbox : Mailbox[M], live~ : Bool, expire~ : Bool) -> Runner[M] {
  { mailbox, live, expire, frames: [], batch: 0, batch_start: 0L }
}

///|
/// Run `first` until it finishes, ends or must wait in the test runner. Each
/// step returns here, so the call stack does not grow with the steps.
async fn[M] Runner::run(self : Runner[M], first : Step[M]) -> RunEnd {
  let mut step = first
  for ;; {
    match step {
      Done => return Finished
      Bounce(next) => step = next()
      Enter(frame, body) => {
        let left = match frame {
          Deadline(limit, _) => limit.to_millis().to_int64()
          Recover(_) | OnClosed(_) => 0L
        }
        self.frames.push({ frame, left })
        step = body()
      }
      Leave(next) => {
        ignore(self.frames.pop())
        step = next()
      }
      Work(work) => step = work() catch { error => self.recover(error) }
      Take(take) =>
        match self.take(take) {
          Go(next) => step = next
          End(end) => return end
        }
      Repeat(repeat) =>
        match self.repeat(repeat) {
          Go(next) => step = next
          End(end) => return end
        }
    }
  }
}

///|
/// Continue with the nearest `recover` of `error`, or raise `error`.
fn[M] Runner::recover(self : Runner[M], error : Error) -> Step[M] raise {
  for index = self.frames.length() - 1; index >= 0; index = index - 1 {
    if self.frames[index].frame is Recover(on_error) {
      self.frames.truncate(index)
      return on_error(error)
    }
  }
  raise error
}

///|
/// Continue with the nearest `on_closed`, or end the run as closed.
fn[M] Runner::closed(self : Runner[M]) -> Turn[M] {
  for index = self.frames.length() - 1; index >= 0; index = index - 1 {
    if self.frames[index].frame is OnClosed(on_closed) {
      self.frames.truncate(index)
      return Go(Bounce(on_closed))
    }
  }
  End(ReceiveClosed)
}

///|
/// The index of the time limit with the least wait time left, the outer one
/// of equal limits.
fn[M] Runner::first_deadline(self : Runner[M]) -> Int? {
  let mut first = None
  for index, entry in self.frames {
    guard entry.frame is Deadline(_, _) else { continue }
    match first {
      Some(earlier) if self.frames[earlier].left <= entry.left => ()
      _ => first = Some(index)
    }
  }
  first
}

///|
/// Count `elapsed` milliseconds of waiting against every time limit.
fn[M] Runner::spend(self : Runner[M], elapsed : Int64) -> Unit {
  for entry in self.frames {
    if entry.frame is Deadline(_, _) {
      entry.left -= elapsed
    }
  }
}

///|
/// Unwind to the time limit at `index` and continue with its `on_timeout`.
fn[M] Runner::expire_at(self : Runner[M], index : Int) -> Step[M] {
  guard self.frames[index].frame is Deadline(_, on_timeout) else {
    abort("not a time limit")
  }
  self.frames.truncate(index)
  Bounce(on_timeout)
}

///|
/// Wait for an arrival. Give `None` when one arrived, or the turn after the
/// nearest time limit expired or the test runner stopped. A time limit counts
/// only the time that its receive waits, so work between two waits does not
/// use it. The test runner has no clock: an expiry moves its time forward by
/// the wait time left of the expired limit.
async fn[M] Runner::wait(self : Runner[M]) -> Turn[M]? {
  self.batch = 0
  let deadline = self.first_deadline()
  guard self.live else {
    return match deadline {
      Some(index) if self.expire => {
        self.spend(self.frames[index].left)
        Some(Go(self.expire_at(index)))
      }
      _ => Some(End(Pending))
    }
  }
  match deadline {
    None => {
      self.mailbox.arrivals.wait()
      None
    }
    Some(index) => {
      let left = self.frames[index].left
      if left <= 0L {
        return Some(Go(self.expire_at(index)))
      }
      let start = @aio.now()
      let arrived = @aio.with_timeout_opt(left.to_int(), () => {
        self.mailbox.arrivals.wait()
      })
      self.spend(@aio.now() - start)
      match arrived {
        Some(_) => None
        None => Some(Go(self.expire_at(index)))
      }
    }
  }
}

///|
/// Count one taken message. After a batch of `BATCH_CHECK` messages that has
/// run for `BATCH_SLICE_MS` or more, let other tasks run.
async fn[M] Runner::count_taken(self : Runner[M]) -> Unit {
  guard self.live else { return }
  if self.batch == 0 {
    self.batch_start = @aio.now()
  }
  self.batch += 1
  if self.batch % BATCH_CHECK == 0 &&
    @aio.now() - self.batch_start >= BATCH_SLICE_MS {
    self.batch = 0
    @aio.pause()
  }
}

///|
/// Take the oldest message that `take` accepts. Check queued messages oldest
/// first before a wait, then continue from the first message not tested.
async fn[M] Runner::take(self : Runner[M], take : Take[M]) -> Turn[M] {
  let mailbox = self.mailbox
  let mut next = 0
  for ;; {
    while next < mailbox.queue.length() {
      let chosen = (take.choose)(mailbox.queue.at(next)) catch {
        error => return Go(self.recover(error))
      }
      if chosen is Some(continue_with) {
        ignore(mailbox.take_at(next))
        self.count_taken()
        return Go(Bounce(continue_with))
      }
      next += 1
    }
    if !mailbox.admitting {
      return self.closed()
    }
    if take.on_empty is Some(on_empty) {
      return Go(Bounce(on_empty))
    }
    if self.wait() is Some(turn) {
      return turn
    }
  }
}

///|
/// Run a loop node: call its handler for each message until it gives a step
/// or the mailbox closes.
async fn[M] Runner::repeat(self : Runner[M], repeat : Repeat[M]) -> Turn[M] {
  let mailbox = self.mailbox
  for ;; {
    if mailbox.queue.length() > 0 {
      let message = mailbox.take_at(0)
      let next = (repeat.handle)(message) catch {
        error => return Go(self.recover(error))
      }
      if next is Some(step) {
        return Go(step)
      }
      self.count_taken()
    } else if !mailbox.admitting {
      return Go(Bounce(repeat.finish))
    } else if self.wait() is Some(turn) {
      return turn
    }
  }
}

///|
/// The end of a run of the test runner.
pub enum TestOutcome[R] {
  /// The receive gave this result.
  Finished(R)
  /// The receive waits for another message.
  Waiting
  /// The receive found the mailbox closed and has no `on_closed`.
  MailboxClosed
}

///|
/// What the test runner does when a receive must wait after the messages.
pub(all) enum TestEnd {
  /// Stop. The outcome is `Waiting`.
  Wait
  /// Expire the time limit that ends first; with no time limit, stop.
  Expire
  /// The mailbox is closed after the messages.
  Close
}

///|
/// The result of a test run: the outcome and the messages that remain.
pub struct TestRun[M, R] {
  priv outcome : TestOutcome[R]
  priv remaining : Array[M]
}

///|
/// How the run ended.
pub fn[M, R] TestRun::outcome(self : TestRun[M, R]) -> TestOutcome[R] {
  self.outcome
}

///|
/// The result, or `None` when the receive did not finish.
pub fn[M, R] TestRun::result(self : TestRun[M, R]) -> R? {
  match self.outcome {
    Finished(value) => Some(value)
    Waiting | MailboxClosed => None
  }
}

///|
/// The messages that the receive did not take, in their order.
pub fn[M, R] TestRun::remaining(self : TestRun[M, R]) -> Array[M] {
  self.remaining.copy()
}

///|
/// Run `receive` against `messages` as a mailbox, with no actor scope, task
/// group or clock. `at_end` says what a receive does when it must wait. An
/// error that no `recover` catches is raised.
pub async fn[M, R] run_test(
  receive : Receive[M, R],
  messages : Array[M],
  at_end? : TestEnd = Wait,
) -> TestRun[M, R] {
  let mailbox = Mailbox::fixed(messages.copy(), admitting=!(at_end is Close))
  let runner = Runner::new(mailbox, live=false, expire=at_end is Expire)
  let result = Ref(None)
  let end = runner.run(
    receive.build(value => {
      result.val = Some(value)
      Done
    }),
  )
  let outcome : TestOutcome[R] = match (end, result.val) {
    (Finished, Some(value)) => Finished(value)
    (Pending, _) => Waiting
    (Finished, None) => abort("a receive finished without a result")
    (ReceiveClosed, _) => MailboxClosed
  }
  { outcome, remaining: mailbox.queue.iter().collect() }
}

///|
/// The result of `receive` against `messages`, or `None` when it waits for
/// another message. See `run_test`.
pub async fn[M, R] run_messages(
  receive : Receive[M, R],
  messages : Array[M],
) -> R? {
  run_test(receive, messages).result()
}
