///|
priv enum ConventionStep {
  AppDirs
  Transform((@conventions.Conventions) -> @conventions.Conventions)
}

///|
/// Transform the host-owned convention set, starting from the empty base set
/// unless app_dirs() has supplied its standard parts. Steps compose in order;
/// a later app_dirs() replaces earlier parts. The final set receives the run's
/// standard flags and resolved environment name.
pub fn[S] conventions(builder : HostBuilder[S], transform : (@conventions.Conventions) -> @conventions.Conventions) -> HostBuilder[S] {
  { ..builder, convention_steps: builder.convention_steps + [Transform(transform)] }
}

///|
/// Enable configuration profiles on the host-owned conventions set. This
/// step adds no discovery parts; use `app_dirs` to discover primary files.
/// A later `app_dirs` replaces earlier convention steps, including this policy.
pub fn[S] profiles(builder : HostBuilder[S], policy : @profiles.Policy) -> HostBuilder[S] {
  builder |> conventions(c => c |> @conventions.profiles(policy))
}

///|
/// Add application sources and formats to the core configuration pipeline.
/// Callbacks run in registration order, after arguments and environment
/// resolution. Sources merge in this order: configure callbacks, the host-owned
/// conventions set (System 100 through UserOverride 400), the <PREFIX>_* source
/// at 600, then argparse overrides at 700.
/// Core load requires priorities that do not go down. With app_dirs() or
/// conventions(f), configure sources must have priority 100 or less, such as
/// defaults or an in-memory value at 0. Put a higher-priority file in the
/// conventions set, or leave out the host-owned set.
/// Conventions added here keep their own discovery options and do not see
/// standard host flags. Use app_dirs() and conventions() for host-owned flag-aware discovery.
/// The run's variable set and working directory replace values that a callback
/// sets; use env_vars or working_dir on the host builder.
/// A callback error ends the run before the factory or any hook.
pub fn[S] configure(builder : HostBuilder[S], sources : (@config.ConfigBuilder) -> @config.ConfigBuilder raise) -> HostBuilder[S] {
  { ..builder, configure_sources: builder.configure_sources + [sources] }
}

///|
/// Supply the immutable file snapshot for wasm and wasm-gc. An incomplete
/// snapshot ends configuration loading with usage code 2 and the requested
/// paths in its error message. Native and js ignore this snapshot and read
/// disk through the config host adapter.
pub fn[S] files(builder : HostBuilder[S], tree : @config.FileTree) -> HostBuilder[S] {
  { ..builder, file_tree: tree }
}

///|
/// Read this application-named key once after loading, before the factory.
/// Its TimeLimit value overrides shutdown_timeout; an absent value keeps
/// the builder limit, which defaults to 30 seconds. A bad value is a
/// configuration error and no factory or hook runs.
pub fn[S] shutdown_timeout_key(builder : HostBuilder[S], key : @config.KeyPath) -> HostBuilder[S] {
  { ..builder, timeout_key: Some(key) }
}

///|
priv struct ConfigurationInputs {
  settings : RunSettings
  parsed : ParsedArguments
  environment : HostEnvironment
  sources : @config.ConfigBuilder
}

///|
fn[S] configuration_inputs(host : Host[S], read_directory? : () -> @lander_core.AbsolutePath raise WorkingDirectoryError = process_directory) -> ConfigurationInputs raise {
  let settings = resolve_settings(host, read_directory~)
  let parsed = parse_arguments(host, env=settings.variables)
  let environment = resolve_environment(host, settings, parsed.discovery_options)
  let options = environment_options(host, parsed.discovery_options, environment)
  let sources = configuration_builder(host, settings, options)
  let sources = match parsed.overrides {
    Some(source) => sources |> @config.add(source)
    None => sources
  }
  { settings, parsed, environment, sources }
}

///|
/// Shared pure load path for an injected tree. `run_embedded` uses it.
// Native and js read disk through `@host.load` and do not call this. Remove the
// override when the build system can limit a function to targets.
#warnings("-1")
fn configuration_from_tree(sources : @config.ConfigBuilder, tree : @config.FileTree) -> @config.Config raise {
  match @config.load(sources, tree) {
    Done(config) => config
    Need(requests) => raise IncompleteFileTree(requests~)
  }
}

///|
// Only `run` (native, js) applies the shutdown timeout; wasm and wasm-gc have no
// timer. Remove when the build system can limit a field read to targets.
#warnings("-7")
priv struct ConfiguredRun[S] {
  context : Context[S]
  shutdown_timeout : @lander_core.TimeLimit
}

///|
fn[S] finish_configuration(host : Host[S], inputs : ConfigurationInputs, config : @config.Config) -> ConfiguredRun[S] raise {
  let shutdown_timeout = match host.timeout_key {
    Some(key) => {
      // Core has no bind by KeyPath yet; follow-up lander-4us.44.
      let limit : @lander_core.TimeLimit? = @config.bind_with(config, key.to_string())
      limit.unwrap_or(host.shutdown_timeout)
    }
    None => host.shutdown_timeout
  }
  let context : BuildContext = { config, environment: inputs.environment, args: inputs.parsed.matches,
    env_vars: inputs.settings.variables, working_dir: inputs.settings.directory }
  let services = (host.factory)(context)
  { context: { services, config, environment: context.environment, args: context.args,
      env_vars: context.env_vars, working_dir: context.working_dir, lifetime: Lifetime::new() }, shutdown_timeout }
}

///|
/// A run that ends before the first hook without a failure: a help or version
/// request of the argument parse, or a factory that raises `StopRequested`.
fn requested_outcome() -> RunOutcome {
  { exit_code: ExitCode::success(), timed_out: false, failures: [], reason: Requested, requested_code: None, signal: None }
}

///|
/// A configuration or factory failure before the engine starts.
fn outcome(error : Error) -> RunOutcome {
  { exit_code: select_exit_code(None, [error], false, None), timed_out: false, failures: [error], reason: StartFailed(error), requested_code: None, signal: None }
}
