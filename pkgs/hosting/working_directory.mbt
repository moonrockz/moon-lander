///|
/// A process working directory that the host cannot read as an absolute path.
// The constructors are used only on native and js, where a process directory
// can be absent or invalid. Remove when embedded targets have process inputs.
#warnings("-6")
pub suberror WorkingDirectoryError {
  /// The process has no working directory.
  MissingWorkingDirectory
  /// The process directory breaks an absolute-path rule.
  InvalidWorkingDirectory(@lander_core.AbsolutePathError)
} derive(Debug)

///|
pub extend WorkingDirectoryError with @debug.Debug::{to_repr}

///|
/// Describe the process directory failure for people.
pub fn WorkingDirectoryError::message(self : WorkingDirectoryError) -> String {
  match self {
    MissingWorkingDirectory => "The process has no working directory"
    InvalidWorkingDirectory(error) => error.message()
  }
}
