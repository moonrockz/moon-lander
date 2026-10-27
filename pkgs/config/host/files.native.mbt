///|
/// Add the answer to one request to the tree.
async fn answer(
  tree : @config.FileTree,
  request : @config.FileRequest,
  platform : @config.Platform,
) -> @config.FileTree raise {
  answer_with(tree, request, platform, native => {
    @fs.kind(native, follow_symlink=true)
  })
}

///|
/// Add the answer to one request to the tree, with `inspect` for the kind of
/// each path. Tests give an `inspect` that fails as a locked file does.
async fn answer_with(
  tree : @config.FileTree,
  request : @config.FileRequest,
  platform : @config.Platform,
  inspect : async (String) -> @fs.FileKind raise,
) -> @config.FileTree raise {
  match request {
    ReadFile(path) => {
      let native = from_slash(path, platform)
      guard kind_of(native, inspect) is Some(Regular) else {
        return tree.with_missing(path)
      }
      tree.with_file(path, @fs.read_file(native).text())
    }
    ListDir(dir) => {
      let native = from_slash(dir, platform)
      guard kind_of(native, inspect) is Some(Directory) else {
        return tree.with_missing(dir)
      }
      let entries : Array[@config.DirEntry] = []
      for name in @fs.readdir(native, include_hidden=true, sort=true) {
        let path = from_slash(join(dir, name), platform)
        if entry_kind(path, inspect) is Some(kind) {
          entries.push({ name, kind })
        }
      }
      tree.with_listing(dir, entries)
    }
  }
}

///|
/// The kind of the file at `native`, through symbolic links, or `None` when
/// nothing is there: the path, or a directory on it, does not exist, or a link
/// points nowhere. Other errors, such as a missing permission, pass out, so an
/// inaccessible file is never reported as absent.
async fn kind_of(
  native : String,
  inspect : async (String) -> @fs.FileKind raise,
) -> @fs.FileKind? raise {
  Some(inspect(native)) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
      None
    error => raise error
  }
}

///|
/// The kind of the listed entry at `native`, or `None` when it no longer
/// exists or is a link that points nowhere. An entry that the system cannot inspect, such as a file that another
/// process locks, is `Inaccessible`, so it does not stop the listing. The load
/// reads it only when it is a candidate, and that read reports the error.
async fn entry_kind(
  native : String,
  inspect : async (String) -> @fs.FileKind raise,
) -> @config.EntryKind? raise {
  let kind = kind_of(native, inspect) catch {
    @os_error.OSError(_) => return Some(Inaccessible)
    error => raise error
  }
  match kind {
    Some(Regular) => Some(File)
    Some(Directory) => Some(Directory)
    Some(_) => Some(Other)
    None => None
  }
}

///|
/// The operating system that runs the program.
fn running_platform() -> @config.Platform {
  match @async.platform {
    Linux => Linux
    MacOS => MacOs
    Windows => Windows
  }
}

///|
fn join(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    "\{dir}/\{name}"
  }
}
