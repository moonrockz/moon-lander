///|
/// Browser boundary failures. Paths are virtual; URLs and response bodies are
/// never included. Core ConfigError values pass through load unchanged.
pub(all) suberror BrowserError {
  InvalidMount(operation~ : String, path~ : String, reason~ : String)
  InvalidPath(operation~ : String, reason~ : String)
  OutsideMount(operation~ : String, path~ : String)
  Unsupported(operation~ : String, path~ : String)
  PermissionDenied(operation~ : String, path~ : String)
  Http(operation~ : String, path~ : String, status~ : Int)
  Io(operation~ : String, path~ : String)
  LimitExceeded(operation~ : String, path~ : String, limit~ : String)
  Aborted(operation~ : String, path~ : String)
  Protocol(operation~ : String, path~ : String)
} derive(Eq, Debug)

///|
pub extend BrowserError with Eq::{equal, not_equal}

///|
pub extend BrowserError with @debug.Debug::{to_repr}

///|
pub fn BrowserError::message(self : BrowserError) -> String {
  match self {
    InvalidMount(operation~, path~, reason~) => "\{operation}: invalid mount \{path}: \{reason}"
    InvalidPath(operation~, reason~) => "\{operation}: invalid virtual path: \{reason}"
    OutsideMount(operation~, path~) => "\{operation}: outside mounts: \{path}"
    Unsupported(operation~, path~) => "\{operation}: unsupported browser capability at \{path}"
    PermissionDenied(operation~, path~) => "\{operation}: permission denied at \{path}"
    Http(operation~, path~, status~) => "\{operation}: HTTP \{status} at \{path}"
    Io(operation~, path~) => "\{operation}: browser I/O failure at \{path}"
    LimitExceeded(operation~, path~, limit~) => "\{operation}: \{limit} limit exceeded at \{path}"
    Aborted(operation~, path~) => "\{operation}: aborted at \{path}"
    Protocol(operation~, path~) => "\{operation}: no progress at \{path}"
  }
}
