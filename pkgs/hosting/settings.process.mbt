///|
/// The sole boundary for omitted native and js variable sets.
fn process_variables() -> Map[String, String] {
  @env.get_env_vars()
}

///|
/// The sole boundary for an omitted process working directory.
fn process_directory() -> @lander_core.AbsolutePath raise WorkingDirectoryError {
  process_directory_from(@env.current_dir)
}

///|
fn process_directory_from(read : () -> String?) -> @lander_core.AbsolutePath raise WorkingDirectoryError {
  guard read() is Some(text) else { raise MissingWorkingDirectory }
  @lander_core.AbsolutePath::parse(text) catch {
    error => raise InvalidWorkingDirectory(error)
  }
}
