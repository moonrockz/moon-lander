///|
/// The immutable application name, optional environment name and content root
/// of a run. Only the host makes this value, from parsed starting settings.
pub struct HostEnvironment {
  /// The application name given to the builder.
  application_name : @lander_core.AppName
  /// The name from the flag, the run's variable set, or the builder default.
  environment_name : @conventions.EnvironmentName?
  /// The builder's content root, else the working directory of the run.
  content_root : @lander_core.AbsolutePath
}

///|
/// Compare the environment name without regard to letter case. With no name,
/// the result is false.
pub fn HostEnvironment::is_environment(self : HostEnvironment, name : @conventions.EnvironmentName) -> Bool {
  self.has_name(name.to_string())
}

///|
/// Whether the environment is Development, without regard to letter case.
pub fn HostEnvironment::is_development(self : HostEnvironment) -> Bool {
  self.has_name("Development")
}

///|
/// Whether the environment is Staging, without regard to letter case.
pub fn HostEnvironment::is_staging(self : HostEnvironment) -> Bool {
  self.has_name("Staging")
}

///|
/// Whether the environment is Production, without regard to letter case.
pub fn HostEnvironment::is_production(self : HostEnvironment) -> Bool {
  self.has_name("Production")
}

///|
fn HostEnvironment::has_name(self : HostEnvironment, name : String) -> Bool {
  match self.environment_name {
    Some(current) => fold_case(current.to_string()) == fold_case(name)
    None => false
  }
}

///|
/// Set the default environment and enable environment files. The flag and the
/// run's prefixed variable still take precedence. A later step replaces the
/// default. Parse the name with `@conventions.EnvironmentName::parse`.
pub fn[S] default_environment(builder : HostBuilder[S], name : @conventions.EnvironmentName) -> HostBuilder[S] {
  { ..builder, environment: Some(name) }
}

///|
/// Set the content root to an absolute path. A later step replaces the value.
/// Without this step, the host uses the working directory of the run.
pub fn[S] content_root(builder : HostBuilder[S], path : @lander_core.AbsolutePath) -> HostBuilder[S] {
  { ..builder, root: Some(path) }
}

///|
/// Resolve after arguments and before configuration, even when environment
/// files are off. Empty variables count as unset, as in conventions. A parsed
/// builder default needs no second parse.
// The embedded driver arrives in group 13. Remove with that caller.
#warnings("-1")
fn[S] resolve_environment(host : Host[S], settings : RunSettings, options : @conventions.DiscoveryOptions) -> HostEnvironment raise @config.ConfigError {
  let variable = "\{host.prefix}_ENVIRONMENT"
  let raw = match (options.environment, settings.variables.get(variable)) {
    (Some(name), _) => Some(name)
    (None, Some(name)) if !name.is_empty() => Some(name)
    _ => None
  }
  let environment_name = match raw {
    Some(text) => Some(@conventions.EnvironmentName::parse(text))
    None => host.environment
  }
  { application_name: host.name, environment_name,
    content_root: host.root.unwrap_or(settings.directory) }
}

///|
/// Convert the resolved name to text only at the conventions input boundary.
// The embedded driver arrives in group 13. Remove with that caller.
#warnings("-1")
fn environment_options(options : @conventions.DiscoveryOptions, environment : HostEnvironment) -> @conventions.DiscoveryOptions {
  { ..options, environment: environment.environment_name.map(name => name.to_string()) }
}
