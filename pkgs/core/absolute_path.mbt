///|
/// A rule of an absolute path.
pub enum AbsolutePathRule {
  /// The path is empty.
  Empty
  /// The path has no absolute root.
  NotAbsolute
  /// A UNC root needs both a server and a share.
  MissingUncServerOrShare
} derive(Eq, Debug)

///|
pub extend AbsolutePathRule with Eq::{equal, not_equal}

///|
pub extend AbsolutePathRule with @debug.Debug::{to_repr}

///|
/// A path that cannot identify an absolute location.
pub suberror AbsolutePathError {
  /// The input text breaks the named rule.
  InvalidAbsolutePath(text~ : String, rule~ : AbsolutePathRule)
} derive(Debug)

///|
pub extend AbsolutePathError with @debug.Debug::{to_repr}

///|
/// Describe the input and the broken rule for people.
pub fn AbsolutePathError::message(self : AbsolutePathError) -> String {
  let InvalidAbsolutePath(text~, rule~) = self
  let reason = match rule {
    Empty => "the path is empty"
    NotAbsolute => "the path must be absolute"
    MissingUncServerOrShare => "a UNC root needs a server and a share"
  }
  "Invalid absolute path \{text.escape()}: \{reason}"
}

///|
/// An absolute location, with `/` separators for Windows forms. A Windows drive
/// root and a UNC root are accepted too. This type suits both working
/// directories and content roots without claiming that the location exists.
pub struct AbsolutePath {
  priv text : String
} derive(Eq, Debug)

///|
pub extend AbsolutePath with Eq::{equal, not_equal}

///|
pub extend AbsolutePath with @debug.Debug::{to_repr}

///|
/// Parse at a path boundary, converting Windows separators once.
pub fn AbsolutePath::parse(text : String) -> AbsolutePath raise AbsolutePathError {
  guard !text.is_empty() else { raise InvalidAbsolutePath(text~, rule=Empty) }
  let chars = Array::from_iter(text.iter())
  let drive = chars.length() >= 3 && is_ascii_letter(chars[0]) && chars[1] == ':' && (chars[2] == '/' || chars[2] == '\\')
  let normalized = if drive || text.has_prefix("\\\\") {
    text.replace_all(old="\\", new="/")
  } else { text }
  guard text.has_prefix("/") || text.has_prefix("\\\\") || drive else {
    raise InvalidAbsolutePath(text~, rule=NotAbsolute)
  }
  if normalized.has_prefix("//") {
    let parts = normalized.split("/").to_array()
    guard parts.length() >= 4 && !parts[2].is_empty() && !parts[3].is_empty() else {
      raise InvalidAbsolutePath(text~, rule=MissingUncServerOrShare)
    }
  }
  { text: normalized }
}

///|
/// The root used by hosts without a process working directory.
pub fn AbsolutePath::root() -> AbsolutePath {
  { text: "/" }
}

///|
/// The path with `/` separators for Windows forms; the text is kept as written.
/// `parse` reads it back to an equal path.
pub impl Show for AbsolutePath with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend AbsolutePath with Show::{output, to_string}
