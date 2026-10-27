///|
/// The kind of a directory entry.
pub(all) enum EntryKind {
  File
  Directory
  Other
  /// The host lists the entry but cannot inspect its kind, for example a file
  /// that another process locks, a link loop, or a missing permission.
  Inaccessible
} derive(Eq, Debug)

///|
pub extend EntryKind with Eq::{equal, not_equal}

///|
pub extend EntryKind with @debug.Debug::{to_repr}

///|
/// One entry of a directory listing, with its real name.
pub(all) struct DirEntry {
  name : String
  kind : EntryKind
} derive(Eq, Debug)

///|
pub extend DirEntry with Eq::{equal, not_equal}

///|
pub extend DirEntry with @debug.Debug::{to_repr}

///|
/// A request that the pure load passes out to a host: the listing of a
/// directory or the text of a file. Paths use `/` separators.
pub(all) enum FileRequest {
  ListDir(String)
  ReadFile(String)
} derive(Eq, Hash, Debug)

///|
pub extend FileRequest with Eq::{equal, not_equal}

///|
pub extend FileRequest with Hash::{hash, hash_combine}

///|
pub extend FileRequest with @debug.Debug::{to_repr}

///|
/// One step of a pure load: the file requests that it still needs, or the
/// result.
pub(all) enum LoadStep[T] {
  Need(Array[FileRequest])
  Done(T)
} derive(Eq, Debug)

///|
pub extend LoadStep with Eq::{equal, not_equal}

///|
pub extend LoadStep with @debug.Debug::{to_repr}

///|
/// What a file tree knows about a path: it holds the value, it records the
/// path as absent, or it does not know.
pub(all) enum Lookup[T] {
  Found(T)
  Missing
  Unknown
} derive(Eq, Debug)

///|
pub extend Lookup with Eq::{equal, not_equal}

///|
pub extend Lookup with @debug.Debug::{to_repr}

///|
/// An immutable snapshot of the files that a load can read: directory
/// listings, file text, and absence records, keyed by path with `/`
/// separators. In a complete tree, a path that the tree does not hold is
/// absent. The pure load asks only for paths that the tree does not know.
pub struct FileTree {
  priv complete : Bool
  priv listings : Map[String, Array[DirEntry]]
  priv files : Map[String, String]
  priv missing : Array[String]
}

///|
/// An empty tree. With `complete=true`, every path is absent until a
/// `with_*` call adds it, so a load over it never asks for files.
pub fn FileTree::new(complete? : Bool = false) -> FileTree {
  { complete, listings: Map([]), files: Map([]), missing: [] }
}

///|
/// A new tree that also holds the listing of the directory `dir`.
pub fn FileTree::with_listing(
  self : FileTree,
  dir : String,
  entries : Array[DirEntry],
) -> FileTree {
  let listings = self.listings.copy()
  listings[dir] = entries.copy()
  { ..self, listings, }
}

///|
/// A new tree that also holds the text of the file `path`.
pub fn FileTree::with_file(
  self : FileTree,
  path : String,
  text : String,
) -> FileTree {
  let files = self.files.copy()
  files[path] = text
  { ..self, files, }
}

///|
/// A new tree that records `path` as absent. When `path` is a directory, every
/// path under it is also absent.
pub fn FileTree::with_missing(self : FileTree, path : String) -> FileTree {
  { ..self, missing: [..self.missing, path] }
}

///|
/// Whether the tree is complete.
pub fn FileTree::is_complete(self : FileTree) -> Bool {
  self.complete
}

///|
/// The text of the file `path`.
pub fn FileTree::file(self : FileTree, path : String) -> Lookup[String] {
  match self.files.get(path) {
    Some(text) => Found(text)
    None => if self.is_absent(path) { Missing } else { Unknown }
  }
}

///|
/// The listing of the directory `dir`.
pub fn FileTree::listing(
  self : FileTree,
  dir : String,
) -> Lookup[Array[DirEntry]] {
  match self.listings.get(dir) {
    Some(entries) => Found(entries.copy())
    None => if self.is_absent(dir) { Missing } else { Unknown }
  }
}

///|
/// Whether `path` exists as a file: the listing of its directory holds its
/// exact name as a file. The compare is case-sensitive on every platform. A
/// missing directory gives `Found(false)`.
///
/// An `Inaccessible` entry with the exact name is a file when the tree holds
/// its text. When the tree does not hold its text, the answer is `Unknown`, and
/// `file_request` asks the host for the file, so the host reports its error. In
/// a complete tree the entry is a file, so a read of it raises file-not-found
/// and the entry never disappears without a report.
pub fn FileTree::is_file(self : FileTree, path : String) -> Lookup[Bool] {
  let (dir, name) = split_path(path)
  match self.listing(dir) {
    Found(entries) => {
      guard entries.iter().find_first(entry => entry.name == name)
        is Some(entry) else {
        return Found(false)
      }
      match entry.kind {
        File => Found(true)
        Inaccessible =>
          match self.file(path) {
            Found(_) => Found(true)
            Missing => Found(self.complete)
            Unknown => Unknown
          }
        Directory | Other => Found(false)
      }
    }
    Missing => Found(false)
    Unknown => Unknown
  }
}

///|
/// The request that answers `is_file(path)` when it gives `Unknown`: the
/// listing of the directory of `path`, or the file itself when the tree holds
/// that listing and the entry is `Inaccessible`.
pub fn FileTree::file_request(self : FileTree, path : String) -> FileRequest {
  let (dir, _) = split_path(path)
  match self.listing(dir) {
    Found(_) => ReadFile(path)
    Missing | Unknown => ListDir(dir)
  }
}

///|
/// Whether `path` is absent: the tree is complete, or it records `path` or a
/// directory above it as missing.
fn FileTree::is_absent(self : FileTree, path : String) -> Bool {
  self.complete ||
  self.missing
  .iter()
  .any(dir => {
    let prefix = if dir.has_suffix("/") { dir } else { dir + "/" }
    path == dir || path.has_prefix(prefix)
  })
}

///|
/// The directory and the name of `path`. A path with no `/` has the directory
/// `.`, and a name directly below the root has the directory `/`. A name
/// directly below a drive has the drive root as its directory, such as `C:/`
/// for `C:/app.toml`, because `C:` alone is the current directory of the drive.
fn split_path(path : String) -> (String, String) {
  match path.rev_find("/") {
    Some(0) => ("/", path[1:].to_owned())
    Some(index) => {
      let dir = path[:index].to_owned()
      let dir = if dir.length() == 2 && dir[1:2] == ":" { dir + "/" } else { dir }
      (dir, path[index + 1:].to_owned())
    }
    None => (".", path)
  }
}
