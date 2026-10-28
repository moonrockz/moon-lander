///|
/// A rule of a log directory.
pub enum LogDirectoryRule {
  /// The path has a NUL character, which no file system accepts.
  NulCharacter
} derive(Eq, Debug)

///|
pub extend LogDirectoryRule with Eq::{equal, not_equal}

///|
pub extend LogDirectoryRule with @debug.Debug::{to_repr}

///|
/// A session setting that breaks a rule. Each case names the input and the rule.
pub suberror SettingsError {
  /// The outstanding record limit is not 1 or more.
  InvalidQueueEventLimit(count~ : Int)
  /// The outstanding payload limit is not 1 byte or more.
  InvalidQueueByteLimit(bytes~ : Int64)
  /// The limit of one record is not 1 byte or more.
  InvalidRecordByteLimit(bytes~ : Int64)
  /// The limit of one record is larger than the outstanding payload limit, so a
  /// record at that limit could never enter the queue.
  RecordLimitAboveQueueLimit(record~ : Int64, queue~ : Int64)
  /// The log directory breaks the named rule.
  InvalidLogDirectory(path~ : String, rule~ : LogDirectoryRule)
  /// Two file destinations use the same directory, stem and format. One file
  /// set has one writer.
  DuplicateFileSet(directory~ : String, name~ : String)
} derive(Debug)

///|
pub extend SettingsError with @debug.Debug::{to_repr}

///|
/// Text for people that names the input and the broken rule.
pub fn SettingsError::message(self : SettingsError) -> String {
  match self {
    InvalidQueueEventLimit(count~) =>
      "Invalid queue event limit \{count}: it must be 1 or more"
    InvalidQueueByteLimit(bytes~) =>
      "Invalid queue byte limit \{bytes}: it must be 1 or more"
    InvalidRecordByteLimit(bytes~) =>
      "Invalid record byte limit \{bytes}: it must be 1 or more"
    RecordLimitAboveQueueLimit(record~, queue~) =>
      "Invalid record byte limit \{record}: it must not be more than the queue byte limit \{queue}"
    InvalidLogDirectory(path~, rule~) => {
      let reason = match rule {
        NulCharacter => "the path has a NUL character"
      }
      "Invalid log directory \{path.escape()}: \{reason}"
    }
    DuplicateFileSet(directory~, name~) =>
      "Two file destinations use the file set \{name.escape()} in \{directory.escape()}"
  }
}

///|
/// The largest count of records that are accepted but not yet written, including
/// the record that the writer writes now.
pub struct QueueEventLimit {
  priv count : Int
} derive(Eq, Debug)

///|
pub extend QueueEventLimit with Eq::{equal, not_equal}

///|
pub extend QueueEventLimit with @debug.Debug::{to_repr}

///|
/// Make a queue event limit. It raises `InvalidQueueEventLimit` when `count` is
/// less than 1.
pub fn QueueEventLimit::count(count : Int) -> QueueEventLimit raise SettingsError {
  guard count >= 1 else { raise InvalidQueueEventLimit(count~) }
  { count, }
}

///|
/// The default limit: 1024 records.
pub fn QueueEventLimit::default() -> QueueEventLimit {
  { count: 1024 }
}

///|
/// The limit as a count of records.
pub fn QueueEventLimit::to_int(self : QueueEventLimit) -> Int {
  self.count
}

///|
/// The largest count of encoded payload bytes that are accepted but not yet
/// written. The count includes the payload of each destination and the record
/// that the writer writes now.
pub struct QueueByteLimit {
  priv bytes : Int64
} derive(Eq, Debug)

///|
pub extend QueueByteLimit with Eq::{equal, not_equal}

///|
pub extend QueueByteLimit with @debug.Debug::{to_repr}

///|
/// Make a queue byte limit. It raises `InvalidQueueByteLimit` when `bytes` is
/// less than 1.
pub fn QueueByteLimit::bytes(bytes : Int64) -> QueueByteLimit raise SettingsError {
  guard bytes >= 1L else { raise InvalidQueueByteLimit(bytes~) }
  { bytes, }
}

///|
/// The default limit: 8 MiB.
pub fn QueueByteLimit::default() -> QueueByteLimit {
  { bytes: 8L * 1024L * 1024L }
}

///|
/// The limit in bytes.
pub fn QueueByteLimit::to_int64(self : QueueByteLimit) -> Int64 {
  self.bytes
}

///|
/// The largest count of encoded bytes of one record, for all its destinations
/// together.
pub struct RecordByteLimit {
  priv bytes : Int64
} derive(Eq, Debug)

///|
pub extend RecordByteLimit with Eq::{equal, not_equal}

///|
pub extend RecordByteLimit with @debug.Debug::{to_repr}

///|
/// Make a record byte limit. It raises `InvalidRecordByteLimit` when `bytes` is
/// less than 1.
pub fn RecordByteLimit::bytes(bytes : Int64) -> RecordByteLimit raise SettingsError {
  guard bytes >= 1L else { raise InvalidRecordByteLimit(bytes~) }
  { bytes, }
}

///|
/// The default limit: 1 MiB.
pub fn RecordByteLimit::default() -> RecordByteLimit {
  { bytes: 1024L * 1024L }
}

///|
/// The limit in bytes.
pub fn RecordByteLimit::to_int64(self : RecordByteLimit) -> Int64 {
  self.bytes
}

///|
/// An absolute directory for log files. It holds an already parsed
/// `AbsolutePath`, so it does not parse the path again; it adds only the rules of
/// file I/O.
pub struct LogDirectory {
  priv path : @lander_core.AbsolutePath
} derive(Eq, Debug)

///|
pub extend LogDirectory with Eq::{equal, not_equal}

///|
pub extend LogDirectory with @debug.Debug::{to_repr}

///|
/// Make a log directory from an absolute path. It raises `InvalidLogDirectory`
/// when the path has a NUL character. Parse relative text against an explicit
/// base at the application boundary first.
pub fn LogDirectory::from_absolute(
  path : @lander_core.AbsolutePath,
) -> LogDirectory raise SettingsError {
  let text = path.to_string()
  guard !text.contains_char('\u{0}') else {
    raise InvalidLogDirectory(path=text, rule=NulCharacter)
  }
  { path, }
}

///|
/// The absolute path of the directory.
pub fn LogDirectory::path(self : LogDirectory) -> @lander_core.AbsolutePath {
  self.path
}

///|
/// The path of the owned log file `name` in the directory, with a `/`
/// separator.
pub fn LogDirectory::file(
  self : LogDirectory,
  name : @rolling.LogFileName,
) -> String {
  self.join(name.to_string())
}

///|
/// The path of the ownership marker of `files` in the directory.
pub fn LogDirectory::marker(
  self : LogDirectory,
  files : @rolling.FileSet,
) -> String {
  self.join(files.marker_name())
}

///|
/// The path of the entry `name` in the directory. Only the typed paths above
/// call it.
fn LogDirectory::join(self : LogDirectory, name : String) -> String {
  let text = self.path.to_string()
  if text.has_suffix("/") {
    text + name
  } else {
    text + "/" + name
  }
}

///|
/// The directory as text.
pub impl Show for LogDirectory with output(self, logger) {
  logger.write_string(self.path.to_string())
}

///|
pub extend LogDirectory with Show::{output, to_string}

///|
/// The process stream of a console destination.
pub(all) enum ConsoleStream {
  /// Standard error, the default, so the program output on standard output
  /// stays free of log records.
  StandardError
  /// Standard output, by explicit selection.
  StandardOutput
} derive(Eq, Debug)

///|
pub extend ConsoleStream with Eq::{equal, not_equal}

///|
pub extend ConsoleStream with @debug.Debug::{to_repr}

///|
/// The stream name: `stderr` or `stdout`.
pub impl Show for ConsoleStream with output(self, logger) {
  logger.write_string(
    match self {
      StandardError => "stderr"
      StandardOutput => "stdout"
    },
  )
}

///|
pub extend ConsoleStream with Show::{output, to_string}

///|
/// When the console writes ANSI styles.
pub(all) enum ColorMode {
  /// Write styles only when the stream is a color terminal, is not redirected,
  /// `TERM` is not `dumb` and `NO_COLOR` is empty or not set.
  Auto
  /// Always write styles, by explicit request.
  Always
  /// Never write styles.
  Never
} derive(Eq, Debug)

///|
pub extend ColorMode with Eq::{equal, not_equal}

///|
pub extend ColorMode with @debug.Debug::{to_repr}

///|
/// What the runtime knows about the terminal of a console stream.
pub(all) enum TerminalCapability {
  /// The stream is a terminal that shows colors.
  ColorTerminal
  /// The stream is a terminal without colors.
  PlainTerminal
  /// The stream goes to a file or a pipe.
  Redirected
  /// The runtime cannot tell. Auto writes no styles.
  Unknown
} derive(Eq, Debug)

///|
pub extend TerminalCapability with Eq::{equal, not_equal}

///|
pub extend TerminalCapability with @debug.Debug::{to_repr}

///|
/// The environment hints for `Auto`, read once at the boundary.
pub struct ColorHints {
  priv no_color : Bool
  priv dumb : Bool
} derive(Eq, Debug)

///|
pub extend ColorHints with Eq::{equal, not_equal}

///|
pub extend ColorHints with @debug.Debug::{to_repr}

///|
/// The hints from the values of `NO_COLOR` and `TERM`. A nonempty `NO_COLOR`
/// turns off Auto colors. `TERM=dumb` turns them off too.
pub fn ColorHints::from_env(no_color~ : String?, term~ : String?) -> ColorHints {
  {
    no_color: no_color is Some(text) && !text.is_empty(),
    dumb: term is Some("dumb"),
  }
}

///|
/// No hint against colors.
pub fn ColorHints::none() -> ColorHints {
  { no_color: false, dumb: false }
}

///|
/// Whether the console writes styles for this mode, terminal and hints.
pub fn ColorMode::styles(
  self : ColorMode,
  capability : TerminalCapability,
  hints : ColorHints,
) -> Bool {
  match self {
    Always => true
    Never => false
    Auto => capability is ColorTerminal && !hints.no_color && !hints.dumb
  }
}

///|
/// A console destination: a stream, a minimum level, a color mode and a theme.
pub struct ConsoleSink {
  priv stream : ConsoleStream
  priv minimum : @logging.Level
  priv color : ColorMode
  priv theme : @formatting.Theme
} derive(Eq, Debug)

///|
pub extend ConsoleSink with Eq::{equal, not_equal}

///|
pub extend ConsoleSink with @debug.Debug::{to_repr}

///|
/// A console destination. The defaults are standard error, `Information`, `Auto`
/// colors and the `Literate` theme.
pub fn ConsoleSink::new(
  stream? : ConsoleStream = StandardError,
  minimum? : @logging.Level = Information,
  color? : ColorMode = Auto,
  theme? : @formatting.Theme = Literate,
) -> ConsoleSink {
  { stream, minimum, color, theme }
}

///|
/// The stream of the destination.
pub fn ConsoleSink::stream(self : ConsoleSink) -> ConsoleStream {
  self.stream
}

///|
/// The lowest level that the destination writes.
pub fn ConsoleSink::minimum(self : ConsoleSink) -> @logging.Level {
  self.minimum
}

///|
/// The color mode of the destination.
pub fn ConsoleSink::color(self : ConsoleSink) -> ColorMode {
  self.color
}

///|
/// The theme that the destination uses when it writes styles.
pub fn ConsoleSink::theme(self : ConsoleSink) -> @formatting.Theme {
  self.theme
}

///|
/// The theme to render with: the destination theme when the mode, terminal and
/// hints permit styles, else `Plain`.
pub fn ConsoleSink::render_theme(
  self : ConsoleSink,
  capability : TerminalCapability,
  hints : ColorHints,
) -> @formatting.Theme {
  if self.color.styles(capability, hints) {
    self.theme
  } else {
    Plain
  }
}

///|
/// A file destination: one rolling file set in one directory.
pub struct FileSink {
  priv directory : LogDirectory
  priv files : @rolling.FileSet
  priv retention : @rolling.Retention
  priv minimum : @logging.Level
}

///|
/// A file destination. The defaults are the `Text` format, daily and 10 MiB
/// rolling, the newest 31 files including the active file, and `Information`.
pub fn FileSink::new(
  directory : LogDirectory,
  stem : @rolling.LogFileStem,
  format? : @rolling.FileFormat = Text,
  policy? : @rolling.RollingPolicy = @rolling.RollingPolicy::default(),
  retention? : @rolling.Retention = @rolling.Retention::default(),
  minimum? : @logging.Level = Information,
) -> FileSink {
  {
    directory,
    files: @rolling.FileSet::new(stem, format, policy),
    retention,
    minimum,
  }
}

///|
/// The directory of the file set.
pub fn FileSink::directory(self : FileSink) -> LogDirectory {
  self.directory
}

///|
/// The file set: stem, format and rolling policy.
pub fn FileSink::files(self : FileSink) -> @rolling.FileSet {
  self.files
}

///|
/// The retention of old files.
pub fn FileSink::retention(self : FileSink) -> @rolling.Retention {
  self.retention
}

///|
/// The lowest level that the destination writes.
pub fn FileSink::minimum(self : FileSink) -> @logging.Level {
  self.minimum
}

///|
/// The path of the ownership marker of the file set.
pub fn FileSink::marker_path(self : FileSink) -> String {
  self.directory.marker(self.files)
}

///|
/// The target of the file set in failures and reports.
pub fn FileSink::target(self : FileSink) -> SinkTarget {
  Files(self.directory, self.files)
}

///|
/// The settings of one logging session: its destinations and its limits.
pub struct SessionSettings {
  priv console : ConsoleSink?
  priv files : Array[FileSink]
  priv event_limit : QueueEventLimit
  priv byte_limit : QueueByteLimit
  priv record_limit : RecordByteLimit
  priv drain_limit : @lander_core.TimeLimit
}

///|
/// The default final drain limit: 5 seconds.
pub fn default_drain_limit() -> @lander_core.TimeLimit {
  @lander_core.TimeLimit::seconds(5) catch {
    _ => abort("5 seconds is a valid time limit")
  }
}

///|
/// Make session settings. The defaults are no console, no files, 1024
/// outstanding records, 8 MiB outstanding payload, 1 MiB per record and a
/// 5-second drain. It raises `RecordLimitAboveQueueLimit` when one record could
/// never enter the queue, and `DuplicateFileSet` when two file destinations use
/// one file set.
pub fn SessionSettings::new(
  console? : ConsoleSink,
  files? : Array[FileSink] = [],
  event_limit? : QueueEventLimit = QueueEventLimit::default(),
  byte_limit? : QueueByteLimit = QueueByteLimit::default(),
  record_limit? : RecordByteLimit = RecordByteLimit::default(),
  drain_limit? : @lander_core.TimeLimit = default_drain_limit(),
) -> SessionSettings raise SettingsError {
  guard record_limit.bytes <= byte_limit.bytes else {
    raise RecordLimitAboveQueueLimit(
      record=record_limit.bytes,
      queue=byte_limit.bytes,
    )
  }
  for i, file in files {
    for j in 0..<i {
      if files[j].directory == file.directory &&
        files[j].files.marker_name() == file.files.marker_name() {
        raise DuplicateFileSet(
          directory=file.directory.to_string(),
          name=file.files.marker_name(),
        )
      }
    }
  }
  {
    console,
    files: files.copy(),
    event_limit,
    byte_limit,
    record_limit,
    drain_limit,
  }
}

///|
/// The standard settings: a console on standard error with the defaults of
/// `ConsoleSink::new`, no files and the default limits.
pub fn SessionSettings::standard() -> SessionSettings {
  {
    console: Some(ConsoleSink::new()),
    files: [],
    event_limit: QueueEventLimit::default(),
    byte_limit: QueueByteLimit::default(),
    record_limit: RecordByteLimit::default(),
    drain_limit: default_drain_limit(),
  }
}

///|
/// The console destination, if any.
pub fn SessionSettings::console(self : SessionSettings) -> ConsoleSink? {
  self.console
}

///|
/// The file destinations, in order. The array is a copy.
pub fn SessionSettings::files(self : SessionSettings) -> Array[FileSink] {
  self.files.copy()
}

///|
/// The outstanding record limit.
pub fn SessionSettings::event_limit(self : SessionSettings) -> QueueEventLimit {
  self.event_limit
}

///|
/// The outstanding payload limit.
pub fn SessionSettings::byte_limit(self : SessionSettings) -> QueueByteLimit {
  self.byte_limit
}

///|
/// The limit of one record.
pub fn SessionSettings::record_limit(self : SessionSettings) -> RecordByteLimit {
  self.record_limit
}

///|
/// The time limit of a final drain.
pub fn SessionSettings::drain_limit(
  self : SessionSettings,
) -> @lander_core.TimeLimit {
  self.drain_limit
}
