///|
/// What a load did with a source.
#derive(Eq, Debug)
pub(all) enum SourceStatus {
  Loaded
  NotFound
  Skipped
}

///|
pub extend SourceStatus with Eq::{equal, not_equal}

///|
pub extend SourceStatus with @debug.Debug::{to_repr}

///|
/// A warning of a load.
#derive(Eq, Debug)
pub(all) enum ConfigWarning {
  /// A source exclusion removed the key that the source held.
  KeyRemoved(KeyPath, Origin)
  /// A warning that a source provider gives.
  Note(source~ : String, message~ : String)
}

///|
pub extend ConfigWarning with Eq::{equal, not_equal}

///|
pub extend ConfigWarning with @debug.Debug::{to_repr}

///|
/// The report of one source after a load. `path` is the file that the source
/// read, and `candidates` are the files that a candidate list looked for.
#derive(Eq, Debug)
pub(all) struct SourceReport {
  kind : SourceKind
  name : String
  priority : Int32
  path : String?
  candidates : Array[String]
  status : SourceStatus
  warnings : Array[ConfigWarning]
}

///|
pub extend SourceReport with Eq::{equal, not_equal}

///|
pub extend SourceReport with @debug.Debug::{to_repr}
