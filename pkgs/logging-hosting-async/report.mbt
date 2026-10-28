///|
/// The operation of a destination that failed.
pub(all) enum SinkOperation {
  /// Create the log directory.
  CreateDirectory
  /// Create the ownership marker of a file set.
  AcquireOwnership
  /// List the log directory.
  ListDirectory
  /// Plan the next file of a file set.
  PlanFile
  /// Open a log file.
  OpenFile
  /// Write a record.
  Write
  /// Close a log file.
  CloseFile
  /// Delete the ownership marker after a normal close.
  ReleaseOwnership
  /// Delete an old file of the file set.
  DeleteOldFile
  /// Wait for the accepted records in a final drain.
  Drain
} derive(Eq, Debug)

///|
pub extend SinkOperation with Eq::{equal, not_equal}

///|
pub extend SinkOperation with @debug.Debug::{to_repr}

///|
/// The operation name for people, for example `write`.
pub impl Show for SinkOperation with output(self, logger) {
  logger.write_string(
    match self {
      CreateDirectory => "create directory"
      AcquireOwnership => "acquire ownership"
      ListDirectory => "list directory"
      PlanFile => "plan file"
      OpenFile => "open file"
      Write => "write"
      CloseFile => "close file"
      ReleaseOwnership => "release ownership"
      DeleteOldFile => "delete old file"
      Drain => "drain"
    },
  )
}

///|
pub extend SinkOperation with Show::{output, to_string}

///|
/// The destination of a failure or a count.
pub(all) enum SinkTarget {
  /// A console stream.
  Console(ConsoleStream)
  /// A file set in a directory.
  Files(LogDirectory, @rolling.FileSet)
} derive(Eq, Debug)

///|
pub extend SinkTarget with Eq::{equal, not_equal}

///|
pub extend SinkTarget with @debug.Debug::{to_repr}

///|
/// The target for people, for example `stderr` or `files /var/log/acme.log.lock`.
pub impl Show for SinkTarget with output(self, logger) {
  match self {
    Console(stream) => logger.write_string(stream.to_string())
    Files(directory, files) =>
      logger.write_string("files \{directory.marker(files)}")
  }
}

///|
pub extend SinkTarget with Show::{output, to_string}

///|
/// A report value that breaks a rule.
pub suberror ReportError {
  /// A count is less than 0.
  NegativeCount(count~ : Int64)
  /// A report says that a drain timed out, but the session is not closed. Only
  /// close has a drain time limit.
  TimeoutBeforeClose
} derive(Debug)

///|
pub extend ReportError with @debug.Debug::{to_repr}

///|
/// Text for people that names the input and the broken rule.
pub fn ReportError::message(self : ReportError) -> String {
  match self {
    NegativeCount(count~) => "Invalid count \{count}: it must be 0 or more"
    TimeoutBeforeClose => "A drain timeout needs a closed session"
  }
}

///|
fn check_counts(counts : Array[Int64]) -> Unit raise ReportError {
  for count in counts {
    guard count >= 0L else { raise NegativeCount(count~) }
  }
}

///|
/// One failure of a destination: the operation, the target, the path or name
/// that the operation used, if any, and the text of the error.
pub struct SinkFailure {
  priv operation : SinkOperation
  priv target : SinkTarget
  priv subject : String?
  priv detail : String
} derive(Eq, Debug)

///|
pub extend SinkFailure with Eq::{equal, not_equal}

///|
pub extend SinkFailure with @debug.Debug::{to_repr}

///|
/// Make a failure report. The runtime and test adapters make these.
pub fn SinkFailure::new(
  operation : SinkOperation,
  target : SinkTarget,
  subject? : String,
  detail : String,
) -> SinkFailure {
  { operation, target, subject, detail }
}

///|
/// The operation that failed.
pub fn SinkFailure::operation(self : SinkFailure) -> SinkOperation {
  self.operation
}

///|
/// The destination of the operation.
pub fn SinkFailure::target(self : SinkFailure) -> SinkTarget {
  self.target
}

///|
/// The path or file name that the operation used, if any.
pub fn SinkFailure::subject(self : SinkFailure) -> String? {
  self.subject
}

///|
/// The text of the error.
pub fn SinkFailure::detail(self : SinkFailure) -> String {
  self.detail
}

///|
/// Text for people, for example
/// `logging: write failed for files /logs/acme.log.lock (acme-20261027.log): disk full`.
pub fn SinkFailure::message(self : SinkFailure) -> String {
  let subject = match self.subject {
    Some(text) => " (\{text})"
    None => ""
  }
  "logging: \{self.operation} failed for \{self.target}\{subject}: \{self.detail}"
}

///|
/// The counts and the latest failures of one destination.
pub struct DestinationReport {
  priv target : SinkTarget
  priv written : Int64
  priv undelivered : Int64
  priv failure : SinkFailure?
  priv retention_failure : SinkFailure?
} derive(Eq, Debug)

///|
pub extend DestinationReport with Eq::{equal, not_equal}

///|
pub extend DestinationReport with @debug.Debug::{to_repr}

///|
/// Make a destination report. The runtime and test adapters make these. It
/// raises `NegativeCount` for a count less than 0.
pub fn DestinationReport::new(
  target : SinkTarget,
  written~ : Int64,
  undelivered~ : Int64,
  failure? : SinkFailure,
  retention_failure? : SinkFailure,
) -> DestinationReport raise ReportError {
  check_counts([written, undelivered])
  { target, written, undelivered, failure, retention_failure }
}

///|
/// The destination.
pub fn DestinationReport::target(self : DestinationReport) -> SinkTarget {
  self.target
}

///|
/// The count of records that the destination wrote.
pub fn DestinationReport::written(self : DestinationReport) -> Int64 {
  self.written
}

///|
/// The count of accepted records for this destination that it did not write,
/// because the destination failed or the final drain ended first.
pub fn DestinationReport::undelivered(self : DestinationReport) -> Int64 {
  self.undelivered
}

///|
/// The failure that stopped the destination, if any. The destination writes no
/// more records after it.
pub fn DestinationReport::failure(self : DestinationReport) -> SinkFailure? {
  self.failure
}

///|
/// The latest retention or ownership-release failure, if any. It does not stop
/// the destination.
pub fn DestinationReport::retention_failure(
  self : DestinationReport,
) -> SinkFailure? {
  self.retention_failure
}

///|
/// The counts of records that the session did not accept, one for each reason.
pub struct DropCounts {
  priv queue_full : Int64
  priv oversized : Int64
  priv closed : Int64
  priv reentrant : Int64
} derive(Eq, Debug)

///|
pub extend DropCounts with Eq::{equal, not_equal}

///|
pub extend DropCounts with @debug.Debug::{to_repr}

///|
/// Make drop counts. The runtime and test adapters make these. It raises
/// `NegativeCount` for a count less than 0.
pub fn DropCounts::new(
  queue_full~ : Int64,
  oversized~ : Int64,
  closed~ : Int64,
  reentrant~ : Int64,
) -> DropCounts raise ReportError {
  check_counts([queue_full, oversized, closed, reentrant])
  { queue_full, oversized, closed, reentrant }
}

///|
/// Records discarded because a queue limit was full.
pub fn DropCounts::queue_full(self : DropCounts) -> Int64 {
  self.queue_full
}

///|
/// Records discarded because they were larger than the record limit.
pub fn DropCounts::oversized(self : DropCounts) -> Int64 {
  self.oversized
}

///|
/// Events received after the session closed.
pub fn DropCounts::closed(self : DropCounts) -> Int64 {
  self.closed
}

///|
/// Events received while the session logger or its failure observer ran, for
/// example a log call from the `Show` of an error or from the observer.
pub fn DropCounts::reentrant(self : DropCounts) -> Int64 {
  self.reentrant
}

///|
/// The sum of all drop counts.
pub fn DropCounts::total(self : DropCounts) -> Int64 {
  self.queue_full + self.oversized + self.closed + self.reentrant
}

///|
/// An immutable snapshot of a session: accepted records, drops, the result of
/// each destination, and whether a drain used its full time limit.
pub struct SessionReport {
  priv accepted : Int64
  priv dropped : DropCounts
  priv destinations : Array[DestinationReport]
  priv drain_timed_out : Bool
  priv closed : Bool
} derive(Eq, Debug)

///|
pub extend SessionReport with Eq::{equal, not_equal}

///|
pub extend SessionReport with @debug.Debug::{to_repr}

///|
/// Make a session report. The runtime and test adapters make these. The report
/// keeps a copy of `destinations`. It raises `NegativeCount` for a count less
/// than 0, and `TimeoutBeforeClose` for a drain timeout of an open session.
pub fn SessionReport::new(
  accepted~ : Int64,
  dropped~ : DropCounts,
  destinations~ : Array[DestinationReport],
  drain_timed_out~ : Bool,
  closed~ : Bool,
) -> SessionReport raise ReportError {
  check_counts([accepted])
  guard !drain_timed_out || closed else { raise TimeoutBeforeClose }
  {
    accepted,
    dropped,
    destinations: destinations.copy(),
    drain_timed_out,
    closed,
  }
}

///|
/// The count of accepted records.
pub fn SessionReport::accepted(self : SessionReport) -> Int64 {
  self.accepted
}

///|
/// The counts of records that the session did not accept.
pub fn SessionReport::dropped(self : SessionReport) -> DropCounts {
  self.dropped
}

///|
/// The report of each destination, console first, then files in settings
/// order. The array is a copy.
pub fn SessionReport::destinations(
  self : SessionReport,
) -> Array[DestinationReport] {
  self.destinations.copy()
}

///|
/// Whether a drain ended at its time limit before all accepted records were
/// written.
pub fn SessionReport::drain_timed_out(self : SessionReport) -> Bool {
  self.drain_timed_out
}

///|
/// Whether the session is closed.
pub fn SessionReport::closed(self : SessionReport) -> Bool {
  self.closed
}

///|
/// Whether delivery failed: a destination failed, a record stayed undelivered,
/// or a drain timed out. Drops at admission and retention failures do not count.
pub fn SessionReport::delivery_failed(self : SessionReport) -> Bool {
  self.drain_timed_out ||
  self.destinations.iter().any(destination => {
    destination.failure is Some(_) || destination.undelivered > 0L
  })
}

///|
/// Each failure in the report, for people, one text for each failure: the
/// destination failures, then the retention failures, then a drain timeout.
pub fn SessionReport::failure_messages(self : SessionReport) -> Array[String] {
  let messages = []
  for destination in self.destinations {
    if destination.failure is Some(failure) {
      messages.push(failure.message())
    }
  }
  for destination in self.destinations {
    if destination.retention_failure is Some(failure) {
      messages.push(failure.message())
    }
  }
  if self.drain_timed_out {
    messages.push(
      "logging: the final drain ended at its time limit before all accepted records were written",
    )
  }
  messages
}
