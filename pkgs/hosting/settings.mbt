///|
/// A variable set supplied as a string map or a JSON object. Conversion runs
/// at the builder step and gives an owned snapshot. The run raises any stored
/// conversion error before argument parsing or configuration I/O.
pub trait IntoEnvVars {
  into_env_vars(Self) -> Map[String, String] raise UsageError
}

///|
pub impl IntoEnvVars for Map[String, String] with into_env_vars(self) {
  self.copy()
}

///|
pub impl IntoEnvVars for Json with into_env_vars(self) {
  guard self is Object(fields) else {
    raise UsageError("The environment-variable set must be a JSON object")
  }
  let vars : Map[String, String] = Map([])
  for key, value in fields {
    match value {
      Null => ()
      String(text) => vars[key] = text
      _ => vars[key] = value.stringify()
    }
  }
  vars
}

///|
/// Replace the prefix for both the variable source and application directories.
pub fn[S] env_prefix(builder : HostBuilder[S], prefix : @lander_core.EnvPrefix) -> HostBuilder[S] {
  { ..builder, prefix }
}

///|
/// Replace the variable set for every reader. Conversion errors end the run
/// with a usage error, before configuration I/O or hooks.
pub fn[S] env_vars(builder : HostBuilder[S], vars : &IntoEnvVars) -> HostBuilder[S] {
  { ..builder, variables: Some(snapshot_variables(vars)) }
}

///|
/// Replace the absolute working directory. The last step wins.
pub fn[S] working_dir(builder : HostBuilder[S], path : @lander_core.AbsolutePath) -> HostBuilder[S] {
  { ..builder, directory: Some(path) }
}

///|
/// Add full variable names that the source must not turn into keys. Names are
/// compared after conversion to upper case, as in the variable source.
/// A later `env_prefix` step does not change these names.
pub fn[S] reserve_env(builder : HostBuilder[S], names : Array[String]) -> HostBuilder[S] {
  { ..builder, reserved: builder.reserved + names }
}

///|
/// Skip only the prefixed configuration source. Other readers keep the set.
pub fn[S] skip_env_source(builder : HostBuilder[S]) -> HostBuilder[S] {
  { ..builder, skip_variables: true }
}

///|
/// Enable application directory discovery with the final name and prefix.
pub fn[S] app_dirs(builder : HostBuilder[S]) -> HostBuilder[S] {
  { ..builder, use_app_dirs: true }
}

///|
priv struct RunSettings {
  variables : @sorted_map.SortedMap[String, String]
  directory : @lander_core.AbsolutePath
}

///|
/// Fill only absent inputs, once. Injectable process readers let portable tests
/// prove that explicit settings never read either process input.
// The embedded driver arrives in group 13. Remove with that caller.
#warnings("-1")
fn[S] resolve_settings(
  host : Host[S],
  read_variables? : () -> Map[String, String] = process_variables,
  read_directory? : () -> @lander_core.AbsolutePath raise WorkingDirectoryError = process_directory,
) -> RunSettings raise {
  let variables = match host.variables {
    Some(Ok(vars)) => vars
    Some(Err(error)) => raise error
    None => @sorted_map.from_iter(read_variables().iter())
  }
  let directory = match host.directory {
    Some(path) => path
    None => read_directory()
  }
  { variables, directory }
}

///|
/// Compose the same inputs for the core source and the conventions reader.
// Group 9 replaces the complete empty tree in the driver with the real load.
// The embedded driver arrives in group 13. Remove with that caller.
#warnings("-1")
fn[S] configuration_builder(host : Host[S], settings : RunSettings, options : @conventions.DiscoveryOptions) -> @config.ConfigBuilder {
  let mut builder = @config.builder()
    |> @config.env_vars(Map::from_iter(settings.variables.iter()))
    |> @config.working_dir(settings.directory.to_string())
  if host.use_app_dirs || host.environment is Some(_) {
    let conventions = if host.use_app_dirs {
      @conventions.app_dirs(host.name.to_string(), prefix=host.prefix.to_string())
    } else {
      @conventions.base(host.name.to_string(), prefix=host.prefix.to_string())
    }
    let conventions = match host.environment {
      Some(name) => conventions |> @conventions.environments(default=name.to_string())
      None => conventions
    }
    builder = builder |> @conventions.add(conventions, options~)
  }
  let prefix = host.prefix.to_string()
  builder |> @config.env(prefix~, reserved=["\{prefix}_ENVIRONMENT", "\{prefix}_HOME"] + host.reserved,
    selection=if host.skip_variables { Skip } else { Discover })
}

///|
// Store failure as data so a non-raising builder step defers the error to run.
#warnings("-78")
fn snapshot_variables(vars : &IntoEnvVars) -> Result[@sorted_map.SortedMap[String, String], UsageError] {
  try { Ok(@sorted_map.from_iter(vars.into_env_vars().iter())) } catch { error => Err(error) }
}
