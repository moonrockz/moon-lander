///|
/// Turn on environments: environment files such as `<app>.Production.<ext>`
/// next to each project-tier primary. The name comes from the `environment`
/// option, then from `<PREFIX>_ENVIRONMENT` in the variable set of the run,
/// then from `default`. With none of them, no environment file loads.
pub fn environments(
  conventions : Conventions,
  default? : String,
) -> Conventions {
  { ..conventions, environments: Some({ default, }) }
}

///|
/// The environment name of the run, or `None` when environments are off or no
/// source gives a name. The sources, from high to low: the `environment` value
/// of `options`, `<PREFIX>_ENVIRONMENT` in `env_vars` (an empty value counts as
/// unset), and the default of `environments`. A name that breaks the name rules
/// raises `InvalidEnvironmentName`, which names the source of the name.
pub fn environment_name(
  conventions : Conventions,
  options? : DiscoveryOptions = DiscoveryOptions::new(),
  env_vars : Map[String, String],
) -> String? raise @config.ConfigError {
  guard conventions.environments is Some(environments) else { return None }
  let variable = "\{conventions.prefix}_ENVIRONMENT"
  let given = match (options.environment, env_vars.get(variable)) {
    (Some(name), _) => Some((name, "the discovery options"))
    (None, Some(name)) if !name.is_empty() => Some((name, variable))
    _ =>
      environments.default.map(name => {
        (name, "the default of \{conventions.display}")
      })
  }
  guard given is Some((name, source)) else { return None }
  check_environment_name(name, source~)
  Some(name)
}

///|
/// Check `name` with the environment name rules: it is not empty, it holds no
/// `/`, `\`, `.` or control character, and it is not `user` or `local` in any
/// letter case. A broken rule raises `InvalidEnvironmentName` with a reason
/// that names `source`, for example `--environment`.
pub fn check_environment_name(
  name : String,
  source~ : String,
) -> Unit raise @config.ConfigError {
  let reason = if name.is_empty() {
    Some("the name is empty")
  } else if name.to_lower() is ("user" | "local") {
    Some("the name is reserved")
  } else if name.iter().any(c => c is ('/' | '\\' | '.') || c.is_control()) {
    Some("the name contains /, \\, . or a control character")
  } else {
    None
  }
  if reason is Some(reason) {
    raise InvalidEnvironmentName(name~, reason="\{reason} (from \{source})")
  }
}

///|
/// The environment-file source next to a primary in `dir` with the file stem
/// `stem`: `<stem>.<name>.<ext>`, with the role `EnvironmentFile`.
fn Conventions::environment_file(
  self : Conventions,
  dir : @config.FileTreePath,
  stem : String,
  name : String,
  extensions : Array[String],
) -> @config.ConfigSource raise @config.ConfigError {
  @config.ConfigSource::candidates(
    texts(extensions.map(extension => dir.child("\{stem}.\{name}.\{extension}"))),
    display=self.display,
    role=EnvironmentFile,
    name=self.display,
  )
}
