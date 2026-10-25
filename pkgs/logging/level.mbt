///|
/// The severity of a log event, from the lowest to the highest, with the names of
/// `Microsoft.Extensions.Logging`. Levels compare in this order.
pub(all) enum Level {
  /// The most detailed steps, for a trace of one run.
  Trace
  /// Facts that help a developer find a fault.
  Debug
  /// The normal flow of the application.
  Information
  /// An unusual event that does not stop the current operation.
  Warning
  /// A fault that stops the current operation.
  Error
  /// A fault that stops the application, or that needs action now.
  Critical
} derive(Eq, Compare, Debug)

///|
pub extend Level with Eq::{equal, not_equal}

///|
pub extend Level with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend Level with @debug.Debug::{to_repr}

///|
/// The level name, for example `Information`.
pub impl Show for Level with output(self, logger) {
  logger.write_string(
    match self {
      Trace => "Trace"
      Debug => "Debug"
      Information => "Information"
      Warning => "Warning"
      Error => "Error"
      Critical => "Critical"
    },
  )
}

///|
pub extend Level with Show::{output, to_string}
