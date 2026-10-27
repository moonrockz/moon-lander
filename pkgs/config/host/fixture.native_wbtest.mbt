///|
/// A temporary directory in the `/` form, removed after the test.
async fn temp_dir() -> String {
  to_slash(@fs.tmpdir(prefix="lander-host"), running_platform())
}

///|
async fn write(path : String, text : String) -> Unit {
  let native = from_slash(path, running_platform())
  match path.rev_find("/") {
    Some(index) =>
      @fs.mkdir(
        from_slash(path[:index].to_owned(), running_platform()),
        recursive=true,
        allow_exist=true,
      )
    None => ()
  }
  @fs.write_file(native, text, create_mode=CreateOrTruncate)
}

///|
async fn remove_dir(path : String) -> Unit {
  @fs.rmdir(path, recursive=true)
}

///|
async fn mkdir(path : String, permission~ : Int) -> Unit {
  @fs.mkdir(path, permission~)
}

///|
async fn chmod(path : String, permission : Int) -> Unit {
  @fs.chmod(path, permission)
}

///|
async fn symlink(target~ : String, path : String) -> Unit {
  @fs.symlink(target~, path)
}

///|
/// An injected fault that is not a system error.
suberror InjectedFault {
  InjectedFault(String)
}

///|
/// The kind of a path, with injected faults: a path in `locked` fails as a file
/// that another process holds open fails on Windows (`ERROR_SHARING_VIOLATION`,
/// 32), a path in `vanished` is gone when the adapter inspects it, and a path
/// in `broken` raises an error that is not a system error.
fn faulty_inspect(
  locked : Array[String],
  vanished : Array[String],
  broken : Array[String],
) -> async (String) -> @fs.FileKind raise {
  async fn(native) {
    let path = to_slash(native, running_platform())
    if locked.contains(path) {
      raise @os_error.OSError(32, context="injected lock on \{path}")
    }
    if broken.contains(path) {
      raise InjectedFault(path)
    }
    let target = if vanished.contains(path) { native + ".vanished" } else { native }
    @fs.kind(target, follow_symlink=true)
  }
}

///|
/// The answer to `request` with the injected faults of `faulty_inspect`.
async fn faulty_answer(
  tree : @config.FileTree,
  request : @config.FileRequest,
  locked~ : Array[String],
  vanished? : Array[String] = [],
  broken? : Array[String] = [],
) -> @config.FileTree raise {
  answer_with(
    tree,
    request,
    running_platform(),
    faulty_inspect(locked, vanished, broken),
  )
}

///|
/// `load` with the injected faults of `faulty_inspect`.
async fn faulty_load(
  builder : @config.ConfigBuilder,
  locked~ : Array[String],
  vanished? : Array[String] = [],
) -> @config.Config raise {
  let inspect = faulty_inspect(locked, vanished, [])
  load_by(builder, async fn(tree, request, platform) {
    answer_with(tree, request, platform, inspect)
  })
}

///|
/// Whether `error` is the error of the native adapter for a file call.
fn is_host_error(error : Error) -> Bool {
  error is @os_error.OSError(_)
}
