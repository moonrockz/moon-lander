///|
/// The rule that a file-tree path text breaks.
pub(all) enum FilePathRule {
  /// The text is empty.
  Empty
  /// The text holds a NUL character.
  Nul
  /// Portable text holds `\`. Use `FileTreePath::from_native` for a Windows
  /// path with native separators.
  Backslash
  /// A drive letter and `:` without `/` after them, such as `C:` or
  /// `C:acme.toml`. Such a path is relative to the current directory of the
  /// drive, so it has no fixed place in the tree.
  DriveRelative
  /// A path that starts with `//` and does not name a server and a share.
  IncompleteUnc
  /// A name for one entry is empty, `.` or `..`, or holds `/`.
  NotAName
} derive(Eq, Debug)

///|
pub extend FilePathRule with Eq::{equal, not_equal}

///|
pub extend FilePathRule with @debug.Debug::{to_repr}

///|
/// The rule in words, for an error message.
pub fn FilePathRule::describe(self : FilePathRule) -> String {
  match self {
    Empty => "the path is empty"
    Nul => "the path holds a NUL character"
    Backslash => "the path holds \\; a portable path uses / separators"
    DriveRelative => "a drive letter and : must have / after them, for example C:/"
    IncompleteUnc => "a path that starts with // must name a server and a share"
    NotAName => "an entry name must not be empty, . or .., and must not hold /"
  }
}

///|
/// The root of a file-tree path.
priv enum PathRoot {
  /// `/`
  Posix
  /// A drive root such as `C:/`, with its letter in the given case.
  Drive(Char)
  /// A UNC share root `//server/share`.
  Unc(String, String)
  /// `.`, the directory that a relative path starts from.
  Current
} derive(Eq, Hash)

///|
/// A path in the file-tree protocol: a root and a list of names, with `/` as
/// the separator on every platform. The root is `/`, a drive root such as
/// `C:/`, a UNC share root such as `//server/share`, or `.` for a relative
/// path. Make a value with `parse` or `from_native`.
///
/// A path keeps the exact case and the order of its names. Empty names and `.`
/// names are left out, so `/w//a/./b/` is `/w/a/b`. A `..` name stays, because
/// the parent of a symbolic link on the disk is not the lexical parent. A path
/// does not tell that a file exists, can be read, or is in a browser mount.
pub struct FileTreePath {
  priv root : PathRoot
  priv names : Array[String]
} derive(Eq, Hash)

///|
pub extend FileTreePath with Eq::{equal, not_equal}

///|
pub extend FileTreePath with Hash::{hash, hash_combine}

///|
/// Parse the portable text form of a path. The text must not be empty, and it
/// must not hold a NUL character or `\`. A drive letter and `:` must have `/`
/// after them, and `//` must start a server and a share name.
pub fn FileTreePath::parse(text : String) -> FileTreePath raise ConfigError {
  fn invalid(rule : FilePathRule) -> ConfigError {
    InvalidFilePath(text~, rule~)
  }

  if text.is_empty() {
    raise invalid(Empty)
  }
  for char in text {
    if char == '\u{0}' {
      raise invalid(Nul)
    }
    if char == '\\' {
      raise invalid(Backslash)
    }
  }
  let chars = Array::from_iter(text.iter())
  let (root, rest) = if text.has_prefix("//") {
    let parts = text[2:].split("/").map(part => part.to_owned()).collect()
    guard parts is [server, share, .. rest] &&
      !server.is_empty() &&
      !share.is_empty() else {
      raise invalid(IncompleteUnc)
    }
    (Unc(server, share), rest.to_owned())
  } else if text.has_prefix("/") {
    (Posix, text[1:].split("/").map(part => part.to_owned()).collect())
  } else if chars.length() >= 2 && chars[0].is_ascii_alphabetic() && chars[1] == ':' {
    guard chars.length() >= 3 && chars[2] == '/' else {
      raise invalid(DriveRelative)
    }
    (Drive(chars[0]), text[3:].split("/").map(part => part.to_owned()).collect())
  } else {
    (Current, text.split("/").map(part => part.to_owned()).collect())
  }
  { root, names: rest.filter(name => name != "" && name != ".") }
}

///|
/// Parse a path in the native form of `platform`. On Windows `\` becomes `/`
/// first, so `C:\w\app.toml` gives `C:/w/app.toml` and `\\server\share\a`
/// gives `//server/share/a`. A drive-relative path such as `C:w` stays an
/// error. On other platforms this is `parse`.
pub fn FileTreePath::from_native(
  text : String,
  platform : Platform,
) -> FileTreePath raise ConfigError {
  match platform {
    Windows =>
      FileTreePath::parse(text.replace_all(old="\\", new="/")) catch {
        InvalidFilePath(rule~, ..) => raise InvalidFilePath(text~, rule~)
        error => raise error
      }
    Linux | MacOs => FileTreePath::parse(text)
  }
}

///|
/// The file-tree path of the host path `path`. This is a checked conversion:
/// `AbsolutePath` uses `/` for drive and UNC paths, but it allows `\` and a NUL
/// character in a POSIX path, which a file-tree path does not.
pub fn FileTreePath::from_absolute(
  path : @lander_core.AbsolutePath,
) -> FileTreePath raise ConfigError {
  FileTreePath::parse(path.to_string())
}

///|
/// The text of the path in the native form of `platform`, for a file-system
/// call. Only Windows paths change: `/` becomes `\`.
pub fn FileTreePath::to_native(
  self : FileTreePath,
  platform : Platform,
) -> String {
  let text = self.to_string()
  match platform {
    Windows => text.replace_all(old="/", new="\\")
    Linux | MacOs => text
  }
}

///|
/// The root of the path: `/`, a drive root, a UNC share root, or `.`.
pub fn FileTreePath::root(self : FileTreePath) -> FileTreePath {
  { root: self.root, names: [] }
}

///|
/// Whether the path is a root: `/`, a drive root, a UNC share root, or `.`.
pub fn FileTreePath::is_root(self : FileTreePath) -> Bool {
  self.names.is_empty()
}

///|
/// Whether the path starts at `/`, a drive root, or a UNC share root, and not
/// at `.`.
pub fn FileTreePath::is_absolute(self : FileTreePath) -> Bool {
  !(self.root is Current)
}

///|
/// The directory that holds the path, or `None` for a root. The parent of
/// `C:/acme.toml` is `C:/`, and the parent of `acme.toml` is `.`.
pub fn FileTreePath::parent(self : FileTreePath) -> FileTreePath? {
  guard !self.names.is_empty() else { None }
  Some({ root: self.root, names: self.names[:self.names.length() - 1].to_owned() })
}

///|
/// The last name of the path, or `None` for a root.
pub fn FileTreePath::name(self : FileTreePath) -> String? {
  self.names.last()
}

///|
/// The names of the path below its root, in order.
pub fn FileTreePath::names(self : FileTreePath) -> Array[String] {
  self.names.copy()
}

///|
/// The path of the entry `name` in the directory `self`. The name must not be
/// empty, `.` or `..`, and must not hold `/`, `\` or a NUL character.
pub fn FileTreePath::child(
  self : FileTreePath,
  name : String,
) -> FileTreePath raise ConfigError {
  if name.is_empty() || name == "." || name == ".." || name.contains("/") {
    raise InvalidFilePath(text=name, rule=NotAName)
  }
  if name.contains("\u{0}") {
    raise InvalidFilePath(text=name, rule=Nul)
  }
  if name.contains("\\") {
    raise InvalidFilePath(text=name, rule=Backslash)
  }
  { root: self.root, names: [..self.names, name] }
}

///|
/// `other` when it is absolute, else `other` below `self`. No `..` name is
/// applied.
pub fn FileTreePath::resolve(
  self : FileTreePath,
  other : FileTreePath,
) -> FileTreePath {
  guard other.root is Current else { other }
  { root: self.root, names: [..self.names, ..other.names] }
}

///|
/// Parse the portable text `relative` and resolve it below `self`. An absolute
/// text gives its own path.
pub fn FileTreePath::join(
  self : FileTreePath,
  relative : String,
) -> FileTreePath raise ConfigError {
  self.resolve(FileTreePath::parse(relative))
}

///|
/// Whether `self` is `ancestor` or below it, name by name: `/w/config2` is not
/// below `/w/config`.
pub fn FileTreePath::is_within(
  self : FileTreePath,
  ancestor : FileTreePath,
) -> Bool {
  self.root == ancestor.root &&
  self.names.length() >= ancestor.names.length() &&
  self.names[:ancestor.names.length()] == ancestor.names[:]
}

///|
/// The longest directory that holds every path in `paths`: the common root
/// and names of their directories. `None` when `paths` is empty or the paths
/// have different roots.
pub fn FileTreePath::common_dir(paths : Array[FileTreePath]) -> FileTreePath? {
  guard paths is [first, .. rest] else { return None }
  let mut dir = first.parent().unwrap_or(first)
  for path in rest {
    while !path.is_within(dir) {
      guard dir.parent() is Some(parent) else { return None }
      dir = parent
    }
  }
  Some(dir)
}

///|
pub impl Show for FileTreePath with output(self, logger) {
  match self.root {
    Posix => logger.write_string("/")
    Drive(letter) => {
      logger.write_char(letter)
      logger.write_string(":/")
    }
    Unc(server, share) => {
      logger.write_string("//\{server}/\{share}")
      if !self.names.is_empty() {
        logger.write_string("/")
      }
    }
    Current =>
      if self.names.is_empty() {
        logger.write_string(".")
      }
  }
  logger.write_string(self.names.join("/"))
}

///|
pub extend FileTreePath with Show::{output, to_string}

///|
/// The debug form is the text form, so a test failure shows `"/w/acme.toml"`.
pub impl @debug.Debug for FileTreePath with to_repr(self) {
  @debug.Repr(self.to_string())
}

///|
pub extend FileTreePath with @debug.Debug::{to_repr}

///|
/// Paths compare by their text form.
pub impl Compare for FileTreePath with compare(self, other) {
  self.to_string().compare(other.to_string())
}

///|
pub extend FileTreePath with Compare::{compare, op_lt, op_le, op_gt, op_ge}
