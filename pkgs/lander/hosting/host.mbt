///|
/// The exit code of a run. 0 is a clean run and 1 is an unhandled failure.
pub(all) struct ExitCode(Int) derive(Eq, Debug)

///|
pub extend ExitCode with Eq::{equal, not_equal}

///|
pub extend ExitCode with @debug.Debug::{to_repr}

///|
/// The values that the services factory gets. The services record does not
/// exist yet, so the factory gets no `Context`.
pub struct BuildContext {
  /// The configuration of the run.
  config : @config.Config
}

///|
/// The values that each hook and the command get. The host makes one context
/// for each run, so each hook and the command see the same services record.
pub struct Context[S] {
  /// The services record that the factory built for this run.
  services : S
  /// The configuration of the run.
  config : @config.Config
}

///|
/// A hook of a hosted service, or the command of a run. It can wait, and it
/// can raise an error.
pub type Hook[S] = async (Context[S]) -> Unit

///|
/// A hosted service: a name and its optional hooks.
priv struct HostedService[S] {
  name : String
  start : Hook[S]?
  stop : Hook[S]?
}

///|
/// The settings of a host before the services factory exists. Each step gives
/// a new builder, so a builder value does not change.
pub struct HostBuilder[S] {
  priv name : String
  priv args : Array[String]
  priv services : Array[HostedService[S]]
}

///|
/// Start a bare host builder with the application name and the command-line
/// arguments. The builder turns on no default.
pub fn[S] builder(name : String, args : Array[String]) -> HostBuilder[S] {
  { name, args: args.copy(), services: [] }
}

///|
/// Add a hosted service. The host runs the `start` hooks in registration order
/// before the command, and the `stop` hooks in reverse order after it. Only a
/// service whose `start` hook succeeded gets its `stop` hook.
pub fn[S] service(
  builder : HostBuilder[S],
  name : String,
  start? : Hook[S],
  stop? : Hook[S],
) -> HostBuilder[S] {
  let services = builder.services.copy()
  services.push({ name, start, stop })
  { ..builder, services, }
}

///|
/// A host that is ready to run. `build` does no I/O, so the same host can run
/// more than one time.
pub struct Host[S] {
  priv name : String
  priv args : Array[String]
  priv services : Array[HostedService[S]]
  priv factory : (BuildContext) -> S raise
}

///|
/// Give the host with the services factory. The run calls the factory one time,
/// after the configuration load and before the first hook.
pub fn[S] build(
  builder : HostBuilder[S],
  factory : (BuildContext) -> S raise,
) -> Host[S] {
  {
    name: builder.name,
    args: builder.args,
    services: builder.services,
    factory,
  }
}

///|
/// The result of a run. The run does not end the process.
pub struct RunOutcome {
  /// 0 for a clean run, 1 when a failure occurred.
  exit_code : ExitCode
  /// Each failure of the factory, a hook or the command, in the order that it
  /// occurred.
  failures : Array[Error]
}
