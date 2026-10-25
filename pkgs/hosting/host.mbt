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
  /// The events, stop requests and cancellation checks of this run.
  lifetime : Lifetime
}

///|
/// A hook of a hosted service, or the command of a run. It can wait, and it
/// can raise an error.
pub type Hook[S] = async (Context[S]) -> Unit

///|
/// A hosted service: a name and its optional hooks.
priv struct HostedService[S] {
  name : ServiceName
  starting : Hook[S]?
  start : Hook[S]?
  started : Hook[S]?
  stopping : Hook[S]?
  stop : Hook[S]?
  stopped : Hook[S]?
}

///|
/// The settings of a host before the services factory exists. Each step gives
/// a new builder, so a builder value does not change.
pub struct HostBuilder[S] {
  priv name : @lander_core.AppName
  priv args : Array[String]
  priv report : ErrorReport?
  priv services : Array[HostedService[S]]
}

///|
/// Start a bare host builder with the application name and the command-line
/// arguments. The builder turns on no default.
pub fn[S] builder(name : @lander_core.AppName, args : Array[String]) -> HostBuilder[S] {
  { name, args: args.copy(), services: [], report: None }
}

///|
/// Add a hosted service with six optional hooks. The host runs all `starting`,
/// then all `start`, then all `started` hooks in registration order. After the
/// command it runs all `stopping`, then all `stop`, then all `stopped` hooks in
/// reverse order, for started services only.
/// A service counts as started when its `start` hook returns without an error,
/// or when the service has no `start` hook, the start phase reached its
/// `starting` step, and its `starting` hook succeeded or is absent.
/// A service that the start phase did not reach is not started.
/// A start failure skips the remaining start hooks and the command. A stop
/// failure does not skip later hooks.
///
/// Each service has its own name, without regard to letter case. A duplicate
/// raises `DuplicateService`. `name` is a `ServiceName`, or a `String` that the
/// step parses; a bad name raises `InvalidServiceName`.
pub fn[S] service(
  builder : HostBuilder[S],
  name : &IntoServiceName,
  starting? : Hook[S],
  start? : Hook[S],
  started? : Hook[S],
  stopping? : Hook[S],
  stop? : Hook[S],
  stopped? : Hook[S],
) -> HostBuilder[S] raise HostError {
  let name = name.into_service_name()
  for service in builder.services {
    if service.name.same_file(name) {
      raise DuplicateService(name~, existing=service.name)
    }
  }
  let services = builder.services.copy()
  services.push({ name, starting, start, started, stopping, stop, stopped })
  { ..builder, services, }
}

///|
/// A host that is ready to run. `build` does no I/O, so the same host can run
/// more than one time.
pub struct Host[S] {
  priv name : @lander_core.AppName
  priv args : Array[String]
  priv report : ErrorReport?
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
    report: builder.report,
  }
}

///|
/// The result of a run. The run does not end the process. Only the run makes an
/// outcome, so the exit code always agrees with the failures.
pub struct RunOutcome {
  priv exit_code : ExitCode
  priv timed_out : Bool
  priv failures : Array[Error]
  priv reason : StopReason
  priv requested_code : ExitCode?
  priv signal : SignalKind?
}

///|
/// The code selected by signal, failure and application-code precedence.
pub fn RunOutcome::exit_code(self : RunOutcome) -> ExitCode {
  self.exit_code
}

///|
/// Each failure of the factory, a hook or the command, in the order that it
/// occurred. The array is a copy.
pub fn RunOutcome::failures(self : RunOutcome) -> Array[Error] {
  self.failures.copy()
}

///|
/// A replacement failure report. It may write asynchronously, and receives the
/// final exit code with each failure, in occurrence order.
/// If a report raises, the driver ignores its error and reports the next failure.
/// A report error cannot change the outcome or make `run` raise.
pub type ErrorReport = async (Error, ExitCode) -> Unit

///|
/// Replace the default standard-error report. At the end of a run with code 1
/// or 2, the driver calls this once per failure. Other codes call no report.
/// If a report raises, the driver ignores its error and reports the next failure.
/// A report error cannot change the outcome or make `run` raise.
pub fn[S] error_report(builder : HostBuilder[S], report : ErrorReport) -> HostBuilder[S] {
  { ..builder, report: Some(report) }
}
