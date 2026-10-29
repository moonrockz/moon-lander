///|
/// A rule broken by a portable virtual-tree path.
pub(all) enum PathRule {
  Empty
  Absolute
  Backslash
  ControlCharacter
  EmptySegment
  DotSegment
} derive(Eq, Debug)

///|
pub extend PathRule with Eq::{equal, not_equal}

///|
pub extend PathRule with @debug.Debug::{to_repr}

///|
/// A path, duplicate entry or tree-structure failure.
pub(all) suberror TreeError {
  InvalidPath(input~ : String, rule~ : PathRule)
  DuplicatePath(TreePath)
  FileDirectoryConflict(TreePath)
} derive(Eq, Debug)

///|
pub extend TreeError with Eq::{equal, not_equal}

///|
pub extend TreeError with @debug.Debug::{to_repr}

///|
/// A nonempty portable path relative to one virtual root. Construction rejects
/// empty, dot and parent segments rather than silently rewriting their meaning.
struct TreePath {
  text : String
} derive(Eq, Hash, Debug)

///|
pub extend TreePath with Eq::{equal, not_equal}

///|
pub extend TreePath with Hash::{hash, hash_combine}

///|
pub extend TreePath with @debug.Debug::{to_repr}

///|
/// Parse a portable relative path once at the input boundary.
pub fn TreePath::parse(input : String) -> TreePath raise TreeError {
  fn invalid(rule : PathRule) -> TreePath raise TreeError {
    raise InvalidPath(input~, rule~)
  }
  if input.is_empty() { return invalid(Empty) }
  if input.has_prefix("/") ||
    (input.length() >= 2 && input.code_unit_at(1) == 58) {
    return invalid(Absolute)
  }
  if input.contains("\\") { return invalid(Backslash) }
  if input.contains("\u{0}") || input.contains("\n") || input.contains("\r") {
    return invalid(ControlCharacter)
  }
  for segment in input.split("/") {
    if segment.is_empty() { return invalid(EmptySegment) }
    if segment == "." || segment == ".." { return invalid(DotSegment) }
  }
  { text: input, }
}

///|
/// Return the exact parsed relative path.
pub fn TreePath::to_string(self : TreePath) -> String {
  self.text
}

///|
/// Return the parent, or None for an entry immediately below the virtual root.
pub fn TreePath::parent(self : TreePath) -> TreePath? {
  let parts = self.text.split("/").to_array()
  if parts.length() == 1 {
    None
  } else {
    Some({ text: parts[:parts.length() - 1].join("/"), })
  }
}

///|
/// One immutable virtual text file. Its content uses LF line endings.
struct TextFile {
  path : TreePath
  source : String
  kernel : @dib.KernelName
} derive(Eq, Debug)

///|
pub extend TextFile with Eq::{equal, not_equal}

///|
pub extend TextFile with @debug.Debug::{to_repr}

///|
/// Construct text from a parsed path and kernel; normalize CRLF and CR to LF.
pub fn TextFile::new(
  path : TreePath,
  source : String,
  kernel~ : @dib.KernelName,
) -> TextFile {
  {
    path,
    source: source.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n"),
    kernel,
  }
}

///|
/// Return this file's parsed path.
pub fn TextFile::path(self : TextFile) -> TreePath { self.path }

///|
/// Return the LF-normalized content, including all boundary lines.
pub fn TextFile::source(self : TextFile) -> String { self.source }

///|
/// Return the content's kernel name. This does not execute the file.
pub fn TextFile::kernel(self : TextFile) -> @dib.KernelName { self.kernel }

///|
/// An immutable ordered collection of files and explicit directories.
/// Parent directories are derived. No entry implies host filesystem access.
struct FileTree {
  files : ReadOnlyArray[TextFile]
  explicit_directories : ReadOnlyArray[TreePath]
  directories : ReadOnlyArray[TreePath]
} derive(Eq, Debug)

///|
pub extend FileTree with Eq::{equal, not_equal}

///|
pub extend FileTree with @debug.Debug::{to_repr}

///|
/// Build a consistent tree, infer parents and reject duplicate files and
/// file/directory collisions. Repeated directory declarations are idempotent.
pub fn FileTree::new(
  files : ReadOnlyArray[TextFile],
  directories~ : ReadOnlyArray[TreePath] = [],
) -> FileTree raise TreeError {
  let names : Map[TreePath, Bool] = Map([])
  for file in files {
    if names.contains(file.path) { raise DuplicatePath(file.path) }
    names[file.path] = true
  }
  let seen : Map[TreePath, Bool] = Map([])
  let all_dirs = []
  let explicit = []
  fn add(path : TreePath) -> Unit raise TreeError {
    if names.contains(path) { raise FileDirectoryConflict(path) }
    if !seen.contains(path) {
      seen[path] = true
      all_dirs.push(path)
    }
  }
  for path in directories {
    if !seen.contains(path) { explicit.push(path) }
    add(path)
  }
  for path in directories.iter().concat(files.iter().map(file => file.path)) {
    let mut parent = path.parent()
    while parent is Some(path) {
      add(path)
      parent = path.parent()
    }
  }
  {
    files: ReadOnlyArray::from_iter(files.iter()),
    explicit_directories: ReadOnlyArray::from_array(explicit[:]),
    directories: ReadOnlyArray::from_array(all_dirs[:]),
  }
}

///|
/// Return files in declaration order.
pub fn FileTree::files(self : FileTree) -> ReadOnlyArray[TextFile] { self.files }

///|
/// Return explicit directories in declaration order.
pub fn FileTree::explicit_directories(self : FileTree) -> ReadOnlyArray[TreePath] {
  self.explicit_directories
}

///|
/// Return explicit and inferred directories, each once.
pub fn FileTree::directories(self : FileTree) -> ReadOnlyArray[TreePath] {
  self.directories
}

///|
/// Find file content by an already parsed path.
pub fn FileTree::file(self : FileTree, path : TreePath) -> TextFile? {
  for file in self.files {
    if file.path == path { return Some(file) }
  }
  None
}
