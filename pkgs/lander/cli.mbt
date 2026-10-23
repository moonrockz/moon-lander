///|
/// Start a host builder for the application `name` with the command-line
/// arguments `args`. The services record is `Unit`.
pub fn cli(name : String, args : Array[String]) -> @hosting.HostBuilder[Unit] {
  @hosting.builder(name, args)
}
