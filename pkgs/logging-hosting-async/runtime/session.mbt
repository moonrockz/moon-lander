///|
/// The text of an adapter error. A cancellation passes out instead, so a
/// cancelled writer stops at once and never reports a healthy destination as
/// failed.
fn failure_text(error : Error) -> String raise {
  if @async.is_being_cancelled() {
    raise error
  }
  error_text(error)
}

///|
/// The text of an error from an adapter.
fn error_text(error : Error) -> String {
  let text = error.to_string()
  if text.is_empty() {
    "unknown error"
  } else {
    text
  }
}

///|
/// The writer of one destination. The session calls `write` from its one
/// writer task, in record order, and `close` one time at the end.
priv struct Output {
  /// Write one payload. It gives the failure that stops the destination, or
  /// `None` when the payload was written.
  write : async (String) -> @sinks.SinkFailure?
  /// Close the resources of the destination. It gives each failure: a
  /// `CloseFile` failure counts against the destination, other failures do not.
  close : async () -> Array[@sinks.SinkFailure]
}

///|
/// One destination of a session, with its counts.
priv struct Sink {
  target : @sinks.SinkTarget
  minimum : @logging.Level
  render : (@formatting.LogRecord) -> String
  output : Output
  mut failure : @sinks.SinkFailure?
  mut retention_failure : @sinks.SinkFailure?
  mut written : Int64
  mut undelivered : Int64
}

///|
fn Sink::new(
  target : @sinks.SinkTarget,
  minimum : @logging.Level,
  render : (@formatting.LogRecord) -> String,
  output : Output,
) -> Sink {
  {
    target,
    minimum,
    render,
    output,
    failure: None,
    retention_failure: None,
    written: 0L,
    undelivered: 0L,
  }
}

///|
/// Whether the destination takes events at `level`.
fn Sink::takes(self : Sink, level : @logging.Level) -> Bool {
  self.failure is None && level >= self.minimum
}

///|
/// One accepted record: its sequence, the payload of each destination (`None`
/// for a destination that does not take it) and its encoded size.
priv struct Pending {
  sequence : Int64
  payloads : Array[String?]
  bytes : Int64
}

///|
/// The mutable state of a session. Only this package changes it. All tasks of
/// one session run in one async runtime, so the state needs no lock.
priv struct Core {
  sinks : Array[Sink]
  event_limit : Int
  byte_limit : Int64
  record_limit : Int64
  drain_limit : Int
  clock : () -> @formatting.LogTimestamp
  observer : ((@sinks.SinkFailure) -> Unit)?
  queue : @deque.Deque[Pending]
  wake : @async.CondVar
  progress : @async.CondVar
  mut queued_bytes : Int64
  mut accepted : Int64
  mut completed : Int64
  mut closed : Bool
  mut stopping : Bool
  mut busy : Bool
  mut writer_done : Bool
  mut drain_timed_out : Bool
  mut queue_full : Int64
  mut oversized : Int64
  mut closed_drops : Int64
  mut reentrant : Int64
  mut cursor : Int
  mut cancel_writer : () -> Unit
  mut final_report : @sinks.SessionReport?
}

///|
fn Core::new(
  settings : @sinks.SessionSettings,
  sinks : Array[Sink],
  clock : () -> @formatting.LogTimestamp,
  observer : ((@sinks.SinkFailure) -> Unit)?,
) -> Core {
  {
    sinks,
    event_limit: settings.event_limit().to_int(),
    byte_limit: settings.byte_limit().to_int64(),
    record_limit: settings.record_limit().to_int64(),
    drain_limit: settings.drain_limit().to_millis(),
    clock,
    observer,
    queue: @deque.Deque([]),
    wake: @async.CondVar::Cond(),
    progress: @async.CondVar::Cond(),
    queued_bytes: 0L,
    accepted: 0L,
    completed: 0L,
    closed: false,
    stopping: false,
    busy: false,
    writer_done: false,
    drain_timed_out: false,
    queue_full: 0L,
    oversized: 0L,
    closed_drops: 0L,
    reentrant: 0L,
    cursor: 0,
    cancel_writer: () => (),
    final_report: None,
  }
}

///|
/// Whether an event at `level` can enter the session.
fn Core::enabled(self : Core, level : @logging.Level) -> Bool {
  !self.closed && self.sinks.iter().any(sink => sink.takes(level))
}

///|
/// Receive one event. It never waits and never raises: it captures the record,
/// renders the payloads, and accepts the record or counts the reason it drops it.
fn Core::receive(self : Core, event : @logging.LogEvent) -> Unit {
  if self.busy {
    self.reentrant += 1L
    return
  }
  if self.closed {
    self.closed_drops += 1L
    return
  }
  self.busy = true
  defer {
    self.busy = false
  }
  let level = event.level
  guard self.sinks.iter().any(sink => sink.takes(level)) else { return }
  let record = @formatting.LogRecord::capture(event, (self.clock)())
  let payloads = self.sinks.map(sink => if sink.takes(level) {
    Some((sink.render)(record))
  } else {
    None
  })
  let bytes = payloads.fold(init=0L, (sum, payload) => match payload {
    Some(text) => sum + @formatting.utf8_length(text)
    None => sum
  })
  if bytes > self.record_limit {
    self.oversized += 1L
    return
  }
  if self.queue.length() >= self.event_limit ||
    self.queued_bytes + bytes > self.byte_limit {
    self.queue_full += 1L
    return
  }
  self.accepted += 1L
  self.queue.push_back({ sequence: self.accepted, payloads, bytes })
  self.queued_bytes += bytes
  self.wake.signal()
}

///|
/// Give `failure` to the observer. A log call from the observer counts as
/// reentrant and is dropped, so a failure is never logged through the session.
fn Core::notify(self : Core, failure : @sinks.SinkFailure) -> Unit {
  guard self.observer is Some(observer) else { return }
  guard !self.busy else { return }
  self.busy = true
  defer {
    self.busy = false
  }
  observer(failure)
}

///|
/// Record a failure that does not stop the destination at `index`.
fn Core::warn(self : Core, index : Int, failure : @sinks.SinkFailure) -> Unit {
  self.sinks[index].retention_failure = Some(failure)
  self.notify(failure)
}

///|
/// The one writer task: write the records in order until the session stops and
/// the queue is empty. A record stays in the queue, and in the queue limits,
/// until each of its destinations wrote it or failed.
async fn Core::run_writer(self : Core) -> Unit {
  // Also a cancelled writer is done, so no drain waits for it.
  defer {
    self.writer_done = true
    self.progress.broadcast()
  }
  while true {
    while self.queue.is_empty() && !self.stopping {
      self.wake.wait()
    }
    guard self.queue.front() is Some(item) else { break }
    for index, sink in self.sinks {
      // The next destination of the front record, for `abandon_queue`.
      self.cursor = index
      guard item.payloads[index] is Some(text) else { continue }
      if sink.failure is Some(_) {
        sink.undelivered += 1L
        continue
      }
      match (sink.output.write)(text) {
        None => sink.written += 1L
        Some(failure) => {
          sink.failure = Some(failure)
          sink.undelivered += 1L
          self.notify(failure)
        }
      }
    }
    ignore(self.queue.pop_front())
    self.cursor = 0
    self.queued_bytes -= item.bytes
    self.completed = item.sequence
    self.progress.broadcast()
  }
}

///|
/// Wait until the writer completed each record that the session accepted
/// before the call. Later records do not make the wait longer. It gives `false`
/// when the writer stopped first.
async fn Core::wait_barrier(self : Core) -> Bool {
  let barrier = self.accepted
  while self.completed < barrier &&
        !self.writer_done &&
        self.final_report is None {
    self.progress.wait()
  }
  self.completed >= barrier
}

///|
/// Count each record that is still in the queue as undelivered for each of its
/// destinations, then empty the queue. The front record counts only from the
/// destination that the stopped writer had not finished.
fn Core::abandon_queue(self : Core) -> Unit {
  let mut first = self.cursor
  while self.queue.pop_front() is Some(item) {
    for index, sink in self.sinks {
      if index >= first && item.payloads[index] is Some(_) {
        sink.undelivered += 1L
      }
    }
    first = 0
    self.queued_bytes -= item.bytes
  }
  self.cursor = 0
}

///|
/// Close the output of each destination one time.
async fn Core::close_outputs(self : Core) -> Unit {
  for index, sink in self.sinks {
    for failure in (sink.output.close)() {
      if failure.operation() is CloseFile && sink.failure is None {
        sink.failure = Some(failure)
        self.notify(failure)
      } else {
        self.warn(index, failure)
      }
    }
  }
}

///|
/// An immutable snapshot of the counts and failures.
fn Core::snapshot(self : Core) -> @sinks.SessionReport {
  self.snapshot_of() catch {
    error => abort("the session keeps its counts valid: \{error.message()}")
  }
}

///|
fn Core::snapshot_of(
  self : Core,
) -> @sinks.SessionReport raise @sinks.ReportError {
  let destinations = []
  for sink in self.sinks {
    destinations.push(
      @sinks.DestinationReport::new(
        sink.target,
        written=sink.written,
        undelivered=sink.undelivered,
        failure?=sink.failure,
        retention_failure?=sink.retention_failure,
      ),
    )
  }
  @sinks.SessionReport::new(
    accepted=self.accepted,
    dropped=@sinks.DropCounts::new(
      queue_full=self.queue_full,
      oversized=self.oversized,
      closed=self.closed_drops,
      reentrant=self.reentrant,
    ),
    destinations~,
    drain_timed_out=self.drain_timed_out,
    closed=self.closed,
  )
}

///|
/// The time that closing gives the cancelled writer to stop, and then the
/// outputs to close, after a drain timeout: 500 ms each, 1 second together.
let close_after_timeout : Int = 500

///|
/// Stop admission, drain within the drain limit, stop the writer and close the
/// outputs. Only the first call does the work; a later call waits for it and
/// gives the same report.
async fn Core::close(self : Core) -> @sinks.SessionReport {
  if self.final_report is Some(report) {
    return report
  }
  if self.closed {
    while self.final_report is None {
      self.progress.wait()
    }
    return self.final_report.unwrap()
  }
  self.closed = true
  @async.protect_from_cancel(() => {
    let finished = @async.with_timeout_opt(self.drain_limit, () => {
      ignore(self.wait_barrier())
      self.stopping = true
      self.wake.broadcast()
      while !self.writer_done {
        self.progress.wait()
      }
      self.close_outputs()
    })
    if finished is None {
      self.drain_timed_out = true
      (self.cancel_writer)()
      // Close the outputs only after the writer stopped using them.
      ignore(
        @async.with_timeout_opt(close_after_timeout, () => {
          while !self.writer_done {
            self.progress.wait()
          }
        }),
      )
      self.abandon_queue()
      ignore(
        @async.with_timeout_opt(close_after_timeout, () => self.close_outputs()),
      )
    }
  })
  let report = self.snapshot()
  self.final_report = Some(report)
  self.progress.broadcast()
  report
}

///|
/// A logging session: one logger, one bounded queue and one writer task.
/// Only `with_session` makes a session.
pub struct Session {
  priv core : Core
}

///|
/// The logger of a session. It implements the synchronous `Logger` trait: a
/// log call captures the record and never waits, raises or writes.
pub struct SessionLogger {
  priv core : Core
}

///|
/// A level is enabled while the session is open and a destination that has not
/// failed takes it. A full queue does not disable a level, so its drops are
/// counted.
pub impl @logging.Logger for SessionLogger with enabled(self, level) {
  self.core.enabled(level)
}

///|
/// Capture the event and accept it, or count the reason it is dropped.
pub impl @logging.Logger for SessionLogger with log(self, event) {
  self.core.receive(event)
}

///|
pub extend SessionLogger with @logging.Logger::{enabled, log}

///|
/// The logger of the session.
pub fn Session::logger(self : Session) -> SessionLogger {
  { core: self.core }
}

///|
/// An immutable snapshot of the counts and failures now.
pub fn Session::status(self : Session) -> @sinks.SessionReport {
  self.core.snapshot()
}

///|
/// Wait until each record accepted before the call is written or accounted for.
/// Records accepted later do not make the wait longer. It gives `true` when
/// the writer reached that point, and `false` when the session closed first.
/// The wait has no time limit of its own; use `@async.with_timeout_opt` to bound it.
pub async fn Session::drain(self : Session) -> Bool {
  self.core.wait_barrier()
}

///|
/// Close the session: stop admission, drain the accepted records within the
/// drain limit, close the files and release their ownership markers, and give
/// the final report. When the drain limit ends first, close stops the writer and
/// gives it and the outputs at most 1 more second, so close takes at most the
/// drain limit plus 1 second. It runs protected from cancellation. A second call gives
/// the same report and closes nothing again. After close, the logger counts each
/// event as closed and its levels are disabled.
pub async fn Session::close(self : Session) -> @sinks.SessionReport {
  self.core.close()
}

///|
/// Run `body` with a new session, then close the session and wait for its
/// writer. The session closes also when `body` raises; the error then passes
/// out after the close. `observer` gets each sink failure outside the logging
/// pipeline; a log call from it is dropped and counted as reentrant.
///
/// `clock` gives the UTC time. The session reads it once for each accepted
/// event, and the file writer reads it to select the rolling period. The
/// default reads `@async.now()`; a test can give a fixed or stepped clock.
pub async fn[X] with_session(
  settings : @sinks.SessionSettings,
  body : async (Session) -> X,
  observer? : (@sinks.SinkFailure) -> Unit,
  clock? : () -> @formatting.LogTimestamp = system_clock,
) -> X {
  run_session(settings, production_sinks, clock, observer, body)
}

///|
/// The body of `with_session`, with the destinations and the clock as inputs,
/// so the tests can give their own.
async fn[X] run_session(
  settings : @sinks.SessionSettings,
  make_sinks : (@sinks.SessionSettings, () -> @formatting.LogTimestamp, (Int, @sinks.SinkFailure) -> Unit) -> Array[Sink],
  clock : () -> @formatting.LogTimestamp,
  observer : ((@sinks.SinkFailure) -> Unit)?,
  body : async (Session) -> X,
) -> X {
  let warnings : Ref[(Int, @sinks.SinkFailure) -> Unit] = { val: (_, _) => () }
  let sinks = make_sinks(settings, clock, (index, failure) => (warnings.val)(
    index, failure,
  ))
  let core = Core::new(settings, sinks, clock, observer)
  warnings.val = (index, failure) => core.warn(index, failure)
  let session : Session = { core, }
  @async.with_task_group(group => {
    let writer = group.spawn(() => core.run_writer(), allow_failure=true)
    core.cancel_writer = () => writer.cancel()
    errdefer ignore(core.close())
    let result = body(session)
    ignore(core.close())
    result
  })
}

///|
/// The UTC time now, from `@async.now()`. A time outside the supported range
/// gives the nearest limit.
fn system_clock() -> @formatting.LogTimestamp {
  let millis = @async.now()
  @formatting.LogTimestamp::from_epoch_millis(millis) catch {
    TimestampOutOfRange(..) =>
      if millis < 0L {
        @formatting.LogTimestamp::earliest()
      } else {
        @formatting.LogTimestamp::latest()
      }
  }
}

///|
/// Write one line to the console stream directly, outside every session. Use
/// it for a final report of sink failures, which must not go through the failed
/// logger. It gives the error text when the write fails.
pub async fn write_diagnostic(
  text : String,
  stream? : @sinks.ConsoleStream = StandardError,
) -> String? {
  write_console(stream, text + "\n")
}

///|
/// A directory entry from an adapter. The size is parsed once here; an entry
/// with a size that is not valid is not regular, so the plan never appends to
/// it and retention never deletes it.
fn listed_file(name : String, size : Int64, regular : Bool) -> @rolling.ListedFile {
  match (try { Some(@rolling.ByteCount::of(size)) } catch { _ => None }) {
    Some(count) => { name, size: count, regular }
    None => { name, size: @rolling.ByteCount::zero(), regular: false }
  }
}
