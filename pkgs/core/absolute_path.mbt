///|
/// A rule of an absolute path.
pub enum AbsolutePathRule {
  /// The path is empty.
  Empty
  /// The path has no absolute root.
  NotAbsolute
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
  }
  "Invalid absolute path \{text.escape()}: \{reason}"
}

///|
/// An absolute location, with `/` separators on every target. A Windows drive
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
  let normalized = text.replace_all(old="\\", new="/")
  let chars = Array::from_iter(normalized.iter())
  let drive = chars.length() >= 3 && is_ascii_letter(chars[0]) && chars[1] == ':' && chars[2] == '/'
  guard text.has_prefix("/") || text.has_prefix("\\\\") || drive else {
    raise InvalidAbsolutePath(text~, rule=NotAbsolute)
  }
  { text: normalized }
}

///|
/// The root used by hosts without a process working directory.
pub fn AbsolutePath::root() -> AbsolutePath {
  { text: "/" }
}

///|
/// The normalized path, which `parse` reads back to an equal path.
pub impl Show for AbsolutePath with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend AbsolutePath with Show::{output, to_string}
