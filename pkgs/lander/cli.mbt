///|
/// Start a host builder for the application `name` with the command-line
/// arguments `args`. The services record is `Unit`.
/// Explicit starting settings replace process inputs. `environment` is a
/// default name, raw text for now; a parsed environment-name type replaces it.
pub fn cli(
  name : @lander_core.AppName,
  args : Array[String],
  env_vars? : &@hosting.IntoEnvVars,
  working_dir? : @lander_core.AbsolutePath,
  environment? : String,
) -> @hosting.HostBuilder[Unit] {
  @hosting.builder(name, args, env_vars?, working_dir?, environment?)
}

///|
/// The application name type of `cli` and its parse error, from
/// `moonrockz/moon-lander-core`.
pub using @lander_core {type AppName, type AppNameError, type AppNameRule}
