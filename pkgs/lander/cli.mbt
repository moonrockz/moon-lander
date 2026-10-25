///|
/// Start a host builder for the application `name` with the command-line
/// arguments `args`. The services record is `Unit`.
/// Explicit starting settings replace process inputs. `environment` is a
/// default name and enables the environments part. Environment files need a
/// primary part such as `@hosting.app_dirs()`. Parse the name with
/// `@lander.EnvironmentName::parse` at the caller boundary.
pub fn cli(
  name : @lander_core.AppName,
  args : Array[String],
  env_vars? : &@hosting.IntoEnvVars,
  working_dir? : @lander_core.AbsolutePath,
  environment? : @conventions.EnvironmentName,
) -> @hosting.HostBuilder[Unit] {
  @hosting.builder(name, args, env_vars?, working_dir?, environment?)
}

///|
/// The application name type of `cli` and its parse error, from
/// `moonrockz/moon-lander-core`.
pub using @lander_core {type AppName, type AppNameError, type AppNameRule}

///|
/// The parsed environment name for the starting default, from
/// `moonrockz/moon-lander-config/conventions`.
pub using @conventions {type EnvironmentName}
