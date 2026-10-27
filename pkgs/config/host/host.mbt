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
/// - Paths use `/` in the tree, reports, and errors. The adapter gives the
///   process working directory in its native form, and the pure load parses it
///   and each file source with `FileTreePath::from_native` for the platform. A
///   file call uses `FileTreePath::to_native`, so on Windows `/` becomes `\`
///   only for the call.
/// - A file or a directory that does not exist becomes an absence record, so
///   no round asks for the same path twice. Other file-system errors, such as a
///   missing permission, pass out of `load`.
/// - A listed entry that the adapter cannot inspect, such as a file that
///   another process locks, is `Inaccessible` in the listing. It stops the load
///   only when the load reads it as a candidate.
#warnings("-67")
pub async fn load(builder : @config.ConfigBuilder) -> @config.Config raise {
  // On js `answer` is synchronous; the wrapper fits it to the async type.
  load_by(builder, async fn(tree, request, platform) {
    answer(tree, request, platform)
  })
}

///|
/// `load` with `answer` for each file request. Tests give an `answer` whose
/// inspection fails as a locked file does.
async fn load_by(
  builder : @config.ConfigBuilder,
  answer : async (@config.FileTree, @config.FileRequest, @config.Platform) -> @config.FileTree raise,
) -> @config.Config raise {
  let platform = builder.given_platform().unwrap_or(running_platform())
  let mut builder = builder |> @config.platform(platform)
  if builder.given_env_vars() is None {
    builder = builder |> @config.env_vars(@env.get_env_vars())
  }
  if builder.given_working_dir() is None && @env.current_dir() is Some(dir) {
    builder = builder |> @config.working_dir(dir)
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
