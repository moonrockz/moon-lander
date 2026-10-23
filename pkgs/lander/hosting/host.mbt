///|
/// The exit code of a run, in the range 0 to 255 that every platform keeps.
pub struct ExitCode {
  priv code : Int
} derive(Eq, Debug)

///|
pub extend ExitCode with Eq::{equal, not_equal}

///|
pub extend ExitCode with @debug.Debug::{to_repr}

///|
/// Make an exit code from a number. It raises `InvalidExitCode` when `code` is
/// not in the range 0 to 255.
pub fn ExitCode::from_int(code : Int) -> ExitCode raise HostError {
  guard code >= 0 && code <= 255 else { raise InvalidExitCode(code~) }
  { code, }
}

///|
/// The exit code 0: a clean run.
pub fn ExitCode::success() -> ExitCode {
  { code: 0 }
}

///|
/// The exit code 1: an unhandled failure.
pub fn ExitCode::failure() -> ExitCode {
  { code: 1 }
}

///|
/// The exit code as a number for the process.
pub fn ExitCode::to_int(self : ExitCode) -> Int {
  self.code
}

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
  name : ServiceName
  start : Hook[S]?
  stop : Hook[S]?
}

///|
/// The settings of a host before the services factory exists. Each step gives
/// a new builder, so a builder value does not change.
pub struct HostBuilder[S] {
  priv name : AppName
  priv args : Array[String]
  priv services : Array[HostedService[S]]
}

///|
/// Start a bare host builder with the application name and the command-line
/// arguments. The builder turns on no default.
pub fn[S] builder(name : AppName, args : Array[String]) -> HostBuilder[S] {
  { name, args: args.copy(), services: [] }
}

///|
/// Add a hosted service. The host runs the `start` hooks in registration order
/// before the command, and the `stop` hooks in reverse order after it. Only a
/// service that started gets its `stop` hook: its `start` hook succeeded, or it
/// has no `start` hook and no earlier `start` hook failed. Each service of a
/// host has its own name: a second service with the same name raises
/// `DuplicateService`.
pub fn[S] service(
  builder : HostBuilder[S],
  name : ServiceName,
  start? : Hook[S],
  stop? : Hook[S],
) -> HostBuilder[S] raise HostError {
  if builder.services.iter().any(service => service.name == name) {
    raise DuplicateService(name~)
  }
  let services = builder.services.copy()
  services.push({ name, start, stop })
  { ..builder, services, }
}

///|
/// A host that is ready to run. `build` does no I/O, so the same host can run
/// more than one time.
pub struct Host[S] {
  priv name : AppName
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
/// The result of a run. The run does not end the process. Only the run makes an
/// outcome, so the exit code always agrees with the failures.
pub struct RunOutcome {
  priv exit_code : ExitCode
  priv failures : Array[Error]
}

///|
/// 0 for a clean run, 1 when a failure occurred.
pub fn RunOutcome::exit_code(self : RunOutcome) -> ExitCode {
  self.exit_code
}

///|
/// Each failure of the factory, a hook or the command, in the order that it
/// occurred. The array is a copy.
pub fn RunOutcome::failures(self : RunOutcome) -> Array[Error] {
  self.failures.copy()
}
