///|
/// Add the answer to one request to the tree.
async fn answer(
  tree : @config.FileTree,
  request : @config.FileRequest,
  platform : @config.Platform,
) -> @config.FileTree raise {
  match request {
    ReadFile(path) => {
      let native = from_slash(path, platform)
      guard kind_of(native) is Some(Regular) else {
        return tree.with_missing(path)
      }
      tree.with_file(path, @fs.read_file(native).text())
    }
    ListDir(dir) => {
      let native = from_slash(dir, platform)
      guard kind_of(native) is Some(Directory) else {
        return tree.with_missing(dir)
      }
      let entries : Array[@config.DirEntry] = []
      for name in @fs.readdir(native, include_hidden=true, sort=true) {
        let kind : @config.EntryKind = match
          kind_of(from_slash(join(dir, name), platform)) {
          Some(Regular) => File
          Some(Directory) => Directory
          _ => Other
        }
        entries.push({ name, kind })
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
async fn kind_of(native : String) -> @fs.FileKind? raise {
  Some(@fs.kind(native, follow_symlink=true)) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
      None
    error => raise error
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
