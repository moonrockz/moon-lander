///|
/// A browser `File` that the application already holds, for example from an
/// HTML file input. The adapter never opens a picker or uploads a file.
#external
pub type File

///|
/// The file name, without a directory. Reading it does not read the contents.
pub extern "js" fn File::name(self : File) -> String =
  #|file => String(file.name)

///|
/// The `webkitRelativePath` of a file from a directory input, or an empty
/// string. The caller maps it explicitly; the adapter does not strip a prefix.
pub extern "js" fn File::webkit_relative_path(self : File) -> String =
  #|file => typeof file.webkitRelativePath === "string" ? file.webkitRelativePath : ""

///|
/// A browser `FileSystemDirectoryHandle` that the application already holds,
/// for example from its own picker or from OPFS. The adapter never opens a
/// picker or requests permission.
#external
pub type DirectoryHandle

///|
/// The backend that answers the reads of one mount.
priv enum Backend {
  Urls(String)
  Files(Map[String, File])
  Directory(DirectoryHandle)
}

///|
/// A read-only, immutable capability for one finite virtual namespace.
pub struct Mount {
  priv root : String
  priv backend : Backend
  priv kinds : Map[String, @config.EntryKind]
  priv listings : Map[String, Array[@config.DirEntry]]
}

///|
pub fn Mount::root(self : Mount) -> String {
  self.root
}

///|
fn validate_path(path : String, absolute~ : Bool, operation~ : String) -> Unit raise BrowserError {
  guard !path.is_empty() && path.has_prefix("/") == absolute else {
    raise InvalidPath(operation~, reason="expected a nonempty canonical path")
  }
  guard !path.contains("\\") && !path.contains("\u{0}") else {
    raise InvalidPath(operation~, reason="backslash or NUL")
  }
  if absolute && path == "/" { return }
  let relative = if absolute { path[1:].to_owned() } else { path }
  guard !(relative.length() >= 2 && relative[1:2] == ":") else {
    raise InvalidPath(operation~, reason="drive prefix")
  }
  for segment in relative.split("/") {
    guard !segment.is_empty() && segment != "." && segment != ".." else {
      raise InvalidPath(operation~, reason="empty, dot, or parent segment")
    }
  }
}

///|
fn contains(root : String, path : String) -> Bool {
  root == "/" || root == path || path.has_prefix(root + "/")
}

///|
fn join(root : String, relative : String) -> String {
  if root == "/" { "/" + relative } else { root + "/" + relative }
}

///|
fn parent(path : String) -> (String, String) {
  match path.rev_find("/") {
    Some(0) => ("/", path[1:].to_owned())
    Some(index) => (path[:index].to_owned(), path[index + 1:].to_owned())
    None => abort("a mounted path is absolute")
  }
}

///|
fn manifest_paths(value : Json, operation : String) -> Array[String] raise BrowserError {
  guard value is Array(items) else {
    raise InvalidMount(operation~, path="", reason="manifest paths must be arrays of strings")
  }
  let paths = []
  for item in items {
    guard item is String(path) else {
      raise InvalidMount(operation~, path="", reason="manifest paths must be strings")
    }
    validate_path(path, absolute=false, operation~)
    paths.push(path)
  }
  paths
}

///|
/// Mount a version-1 JSON manifest at a canonical absolute virtual root. This
/// validates inputs without fetching. No URL can be supplied by an entry.
pub fn from_urls(base : String, manifest : Json, root~ : String) -> Mount raise BrowserError {
  let operation = "from_urls"
  validate_path(root, absolute=true, operation~)
  let normalized = adapter.normalize_base(base)
  guard normalized != "" else {
    raise InvalidMount(operation~, path=root, reason="expected an HTTP(S) directory base without credentials, query, or fragment")
  }
  guard manifest is Object(fields) && fields.get("version") is Some(Number(version, ..)) && version == 1.0 && fields.get("files") is Some(files) else {
    raise InvalidMount(operation~, path=root, reason="expected manifest version 1 and files array")
  }
  for key, _ in fields {
    guard key == "version" || key == "files" || key == "directories" else {
      raise InvalidMount(operation~, path=root, reason="unknown manifest field")
    }
  }
  let files = manifest_paths(files, operation)
  let directories = match fields.get("directories") {
    Some(value) => manifest_paths(value, operation)
    None => []
  }
  let (kinds, listings) = finite_namespace(root, files, directories, operation)
  { root, backend: Urls(normalized), kinds, listings }
}

///|
/// Infer the finite namespace of declared files and empty directories. Reject
/// duplicates, file/directory collisions and file ancestors before any I/O.
fn finite_namespace(
  root : String,
  files : Array[String],
  directories : Array[String],
  operation : String,
) -> (Map[String, @config.EntryKind], Map[String, Array[@config.DirEntry]]) raise BrowserError {
  let kinds : Map[String, @config.EntryKind] = Map::from_array([(root, Directory)])
  let declared : Set[String] = Set([])
  for entries in [(files, @config.EntryKind::File), (directories, @config.EntryKind::Directory)] {
    for relative in entries.0 {
      let path = join(root, relative)
      guard !declared.contains(path) else {
        raise InvalidMount(operation~, path~, reason="duplicate entry")
      }
      declared.add(path)
      if kinds.get(path) is Some(previous) && previous != entries.1 {
        raise InvalidMount(operation~, path~, reason="file/directory collision")
      }
      kinds[path] = entries.1
      let mut ancestor = parent(path).0
      while ancestor != root {
        if kinds.get(ancestor) is Some(File) {
          raise InvalidMount(operation~, path=ancestor, reason="file used as a directory")
        }
        kinds[ancestor] = Directory
        ancestor = parent(ancestor).0
      }
    }
  }
  let listings : Map[String, Array[@config.DirEntry]] = Map([])
  for path, kind in kinds {
    if kind == Directory { listings[path] = [] }
  }
  for path, kind in kinds {
    if path != root {
      let (dir, name) = parent(path)
      listings[dir].push({ name, kind })
    }
  }
  for _, entries in listings {
    entries.sort_by((a, b) => a.name.lexical_compare(b.name))
  }
  (kinds, listings)
}

///|
/// Mount explicit relative-path and browser `File` pairs at a canonical absolute
/// virtual root. Parent listings are inferred. No file content is read here;
/// a load reads a file only when the core requests it.
pub fn from_files(files : Array[(String, File)], root~ : String) -> Mount raise BrowserError {
  let operation = "from_files"
  validate_path(root, absolute=true, operation~)
  let paths = []
  let selected : Map[String, File] = Map([])
  for entry in files {
    let (relative, file) = entry
    validate_path(relative, absolute=false, operation~)
    paths.push(relative)
    selected[relative] = file
  }
  let (kinds, listings) = finite_namespace(root, paths, [], operation)
  { root, backend: Files(selected), kinds, listings }
}

///|
/// Mount a caller-supplied directory handle at a canonical absolute virtual
/// root. This is a live, read-only mount: a load lists and reads entries below
/// the handle one segment at a time with `create: false`, and never writes.
/// Each load caches its answers; a later load can see changed entries.
pub fn from_directory(handle : DirectoryHandle, root~ : String) -> Mount raise BrowserError {
  validate_path(root, absolute=true, operation="from_directory")
  { root, backend: Directory(handle), kinds: Map::from_array([(root, Directory)]), listings: Map([]) }
}
