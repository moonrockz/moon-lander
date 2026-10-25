///|
/// Load the configuration from the disk. This is the host side of the pure
/// `@config.load`: it fills the inputs that the builder does not hold, then
/// answers each file request until the load is done.
/// Native and js only; on wasm and wasm-gc use @config.load(builder, tree) or @hosting.files(tree).
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
#warnings("-67")
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
