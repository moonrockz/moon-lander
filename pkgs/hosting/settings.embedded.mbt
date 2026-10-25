///|
fn process_variables() -> Map[String, String] {
  {}
}

///|
// Match the process reader signature; embedded roots cannot fail.
#warnings("-24")
fn process_directory() -> @lander_core.AbsolutePath raise WorkingDirectoryError {
  @lander_core.AbsolutePath::root()
}
