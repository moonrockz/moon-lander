///|
/// Load the configuration from the disk. This is the host side of the pure
/// `@config.load`: it fills the inputs that the builder does not hold, then
/// answers each file request until the load is done.
///
/// - The variable set and the working directory of the builder win. Only when
///   the builder holds none does the adapter read the process environment or
///   the process working directory.
/// - The platform comes from the builder, else from the running system.
/// - Paths use `/` in the tree, reports, and errors. On Windows the adapter
///   converts `\` to `/` when it reads a path and back for each file call.
/// - A file or a directory that does not exist becomes an absence record, so
///   no round asks for the same path twice. Other file-system errors, such as a
///   missing permission, pass out of `load`.
pub async fn load(builder : @config.ConfigBuilder) -> @config.Config raise {
  let platform = builder.given_platform().unwrap_or(running_platform())
  let mut builder = builder |> @config.platform(platform)
  if builder.given_env_vars() is None {
    builder = builder |> @config.env_vars(@env.get_env_vars())
  }
  if builder.given_working_dir() is None && @env.current_dir() is Some(dir) {
    builder = builder |> @config.working_dir(to_slash(dir, platform))
  }
  let mut tree = @config.FileTree::new()
  while true {
    match @config.load(builder, tree) {
      Done(config) => return config
      Need(requests) =>
        for request in requests {
          tree = answer(tree, request, platform)
        }
    }
  }
  abort("the load loop ends only with a configuration")
}

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
/// `path` with `/` separators. Only Windows paths change.
fn to_slash(path : String, platform : @config.Platform) -> String {
  match platform {
    Windows => path.replace_all(old="\\", new="/")
    _ => path
  }
}

///|
/// `path` with the native separators of `platform`, for a file call.
fn from_slash(path : String, platform : @config.Platform) -> String {
  match platform {
    Windows => path.replace_all(old="/", new="\\")
    _ => path
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
