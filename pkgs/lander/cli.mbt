///|
/// Start a host builder for the application `name` with the command-line
/// arguments `args`. The services record is `Unit`.
pub fn cli(
  name : @lander_core.AppName,
  args : Array[String],
) -> @hosting.HostBuilder[Unit] {
  @hosting.builder(name, args)
}

///|
/// The application name type of `cli`, from `moonrockz/moon-lander-core`.
pub using @lander_core {type AppName}
