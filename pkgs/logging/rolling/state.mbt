///|
/// One entry of a log directory, as the host adapter found it. The adapter
/// gives the entries; this package does no I/O.
pub(all) struct ListedFile {
  /// The entry name, with no directory part.
  name : String
  /// The size. Only the size of a regular file has an effect.
  size : ByteCount
  /// True for a regular file. False for a directory, a symbolic link and each
  /// other kind of entry: the plan never appends to them and retention never
  /// deletes them.
  regular : Bool
} derive(Eq, Debug)

///|
pub extend ListedFile with Eq::{equal, not_equal}

///|
pub extend ListedFile with @debug.Debug::{to_repr}

///|
/// The file action for the next record. The adapter does the action, and then
/// tells the state the result with `opened` and `wrote`.
pub(all) enum FilePlan {
  /// Write the record to the open active file.
  Append(LogFileName)
  /// No file is open: open this file to append, and then write the record. At a
  /// restart this can be an existing file with `existing_size` bytes; the
  /// adapter never truncates it.
  Open(LogFileName, existing_size~ : ByteCount)
  /// Close the active file, open this file to append, and then write the
  /// record. After the open, run retention. When the period changed, this can
  /// be an existing file of the new period with `existing_size` bytes.
  Roll(LogFileName, existing_size~ : ByteCount)
} derive(Eq, Debug)

///|
pub extend FilePlan with Eq::{equal, not_equal}

///|
pub extend FilePlan with @debug.Debug::{to_repr}

///|
/// The rolling state of one writer of a file set: the active file and its size.
/// The value is immutable: `opened` and `wrote` give a new state. The adapter
/// calls them only after its I/O succeeds, so a failed action does not move the
/// state.
pub struct RollingState {
  priv set : FileSet
  priv active : LogFileName?
  priv size : ByteCount
} derive(Eq, Debug)

///|
pub extend RollingState with Eq::{equal, not_equal}

///|
pub extend RollingState with @debug.Debug::{to_repr}

///|
/// The state of a writer of `set` that has no open file.
pub fn RollingState::new(set : FileSet) -> RollingState {
  { set, active: None, size: ByteCount::zero() }
}

///|
/// The file set of the writer.
pub fn RollingState::file_set(self : RollingState) -> FileSet {
  self.set
}

///|
/// The open active file, or `None` before the first open.
pub fn RollingState::active(self : RollingState) -> LogFileName? {
  self.active
}

///|
/// The bytes in the active file: its size at the open and each write after it.
pub fn RollingState::size(self : RollingState) -> ByteCount {
  self.size
}

///|
/// True when a file with `size` bytes can take a record of `record_bytes`
/// bytes: the file is empty, the policy has no size limit, or the record fits in
/// the limit. An exact fit is allowed.
fn FileSet::has_room(
  self : FileSet,
  size : ByteCount,
  record_bytes : ByteCount,
) -> Bool {
  match self.limit() {
    None => true
    Some(limit) =>
      size.bytes == 0L || record_bytes.bytes <= limit.to_int64() - size.bytes
  }
}

///|
/// True when the next plan at `now` reads the directory listing: no file is
/// open yet, or a daily policy moves to a later UTC day. Read the clock once and
/// give the same `now` to `plan`.
pub fn RollingState::needs_listing(
  self : RollingState,
  now : @formatting.LogTimestamp,
) -> Bool {
  match self.active {
    None => true
    Some(active) => active.epoch_day() is Some(day) && now.epoch_day() > day
  }
}

///|
/// The file action for a record of `record_bytes` bytes (the UTF-8 bytes of the
/// rendered record, including its LF) at the writer time `now`.
///
/// - With no open file, the plan reads `listing`, the entries of the log
///   directory. It finds the newest owned file of the current period (the UTC
///   day of `now` for a daily policy, all owned files for `Size`). When that is
///   a regular file with room for the record, the plan opens it to append. When
///   it is not, the plan opens the next sequence number. With no owned file, it
///   opens the first name of the period.
/// - With an open file and a later UTC day, a daily policy rolls. It reads
///   `listing` for the files of the new day, as at a restart, so a file that an
///   earlier run left for that day is appended to when it has room, else the
///   next sequence number opens. A clock that moves back does not roll: the
///   writer stays in the day of the active file.
/// - Otherwise the plan does not read `listing`; `needs_listing` tells when it
///   does.
/// - A size limit rolls a nonempty file when the record does not fit. An empty
///   file takes a record larger than the limit, and the next record rolls. The
///   plan never splits a record.
///
/// Raises `SequenceExhausted` when the period has no next name.
pub fn RollingState::plan(
  self : RollingState,
  now : @formatting.LogTimestamp,
  record_bytes : ByteCount,
  listing : Array[ListedFile],
) -> FilePlan raise RollingError {
  let set = self.set
  match self.active {
    None => {
      let (name, existing_size) = set.period_plan(now, record_bytes, listing)
      Open(name, existing_size~)
    }
    Some(active) =>
      if active.epoch_day() is Some(day) && now.epoch_day() > day {
        let (name, existing_size) = set.period_plan(now, record_bytes, listing)
        Roll(name, existing_size~)
      } else if set.has_room(self.size, record_bytes) {
        Append(active)
      } else {
        Roll(set.next_name(active), existing_size=ByteCount::zero())
      }
  }
}

///|
/// The file to open for the period of `now`, from the directory entries, and
/// its size: the newest owned file of the period when it is regular and has
/// room, else the next name, else the first name of the period.
fn FileSet::period_plan(
  self : FileSet,
  now : @formatting.LogTimestamp,
  record_bytes : ByteCount,
  listing : Array[ListedFile],
) -> (LogFileName, ByteCount) raise RollingError {
  let today = now.epoch_day()
  let mut newest : (LogFileName, ListedFile)? = None
  for file in listing {
    guard self.parse_name(file.name) is Some(name) else { continue }
    guard !self.is_daily() || name.epoch_day() == Some(today) else { continue }
    match newest {
      Some((known, _)) if known >= name => ()
      _ => newest = Some((name, file))
    }
  }
  match newest {
    None => (self.first_name(now), ByteCount::zero())
    Some((name, file)) =>
      if file.regular && self.has_room(file.size, record_bytes) {
        (name, file.size)
      } else {
        (self.next_name(name), ByteCount::zero())
      }
  }
}

///|
/// The state after the adapter opened `name` to append, with `size` bytes in it
/// after the open.
pub fn RollingState::opened(
  self : RollingState,
  name : LogFileName,
  size : ByteCount,
) -> RollingState {
  { ..self, active: Some(name), size }
}

///|
/// The state after the adapter wrote `bytes` bytes to the active file.
pub fn RollingState::wrote(
  self : RollingState,
  bytes : ByteCount,
) -> RollingState {
  { ..self, size: { bytes: self.size.bytes + bytes.bytes } }
}

///|
/// The owned files to delete under `retention`, after `active` opened.
/// Only regular entries of `listing` whose names have the complete owned form
/// count, so directories, links, the marker and other names stay. The active
/// file is never in the result. `KeepNewest(n)` keeps the active file and the
/// newest `n - 1` other owned files, by UTC day and then by sequence number, not
/// by modification time. The result is oldest first. `KeepAll` deletes nothing.
pub fn FileSet::retention(
  self : FileSet,
  retention : Retention,
  listing : Array[ListedFile],
  active : LogFileName,
) -> Array[LogFileName] {
  guard retention is KeepNewest(count) else { return [] }
  let owned : Array[LogFileName] = []
  for file in listing {
    guard file.regular else { continue }
    guard self.parse_name(file.name) is Some(name) else { continue }
    guard name != active && !owned.contains(name) else { continue }
    owned.push(name)
  }
  owned.sort()
  let keep = count.to_int() - 1
  let delete = if owned.length() > keep { owned.length() - keep } else { 0 }
  owned[0:delete].to_owned()
}
