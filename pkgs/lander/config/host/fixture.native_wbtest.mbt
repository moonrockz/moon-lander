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
