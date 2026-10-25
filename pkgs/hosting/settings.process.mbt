///|
/// The sole boundary for omitted native and js variable sets.
fn process_variables() -> Map[String, String] {
  @env.get_env_vars()
}

///|
/// The sole boundary for an omitted process working directory.
fn process_directory() -> @lander_core.AbsolutePath {
  @lander_core.AbsolutePath::parse(@env.current_dir().unwrap_or("/")) catch {
    _ => abort("the process working directory is absolute")
  }
}
