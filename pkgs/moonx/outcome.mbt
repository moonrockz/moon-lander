///|
/// A full process status bit pattern. Windows keeps all 32 bits; POSIX process
/// boundaries retain the low byte. The driver normalizes a POSIX signal result
/// before constructing this value.
pub struct ProcessStatus {
  priv bits : UInt
} derive(Eq, Debug)

///|
pub extend ProcessStatus with Eq::{equal, not_equal}

///|
pub extend ProcessStatus with @debug.Debug::{to_repr}

///|
/// Every unsigned 32-bit pattern is a valid Windows process status.
pub fn ProcessStatus::from_bits(bits : UInt) -> ProcessStatus { { bits, } }

///|
/// A successful finite process completion.
pub fn ProcessStatus::success() -> ProcessStatus { { bits: 0U } }

///|
/// The conventional unhandled-failure status.
pub fn ProcessStatus::failure() -> ProcessStatus { { bits: 1U } }

///|
/// The complete unsigned status bit pattern.
pub fn ProcessStatus::bits(self : ProcessStatus) -> UInt { self.bits }

///|
/// Signed representation accepted by the process exit boundary, without losing
/// Windows status bits.
pub fn ProcessStatus::to_int(self : ProcessStatus) -> Int { self.bits.reinterpret_as_int() }

///|
/// Whether the complete status is zero.
pub fn ProcessStatus::is_success(self : ProcessStatus) -> Bool { self.bits == 0U }

///|
/// OS identity, independent of platform-specific signal numbers.
pub(all) enum LauncherSignal {
  Interrupt
  Terminate
  Hangup
  Break
} derive(Eq, Debug)

///|
pub extend LauncherSignal with Eq::{equal, not_equal}

///|
pub extend LauncherSignal with @debug.Debug::{to_repr}

///|
/// Distinguish an observed OS signal from ordinary cancellation.
pub(all) enum CancellationCause {
  Signal(LauncherSignal)
  Requested
} derive(Debug)

///|
pub extend CancellationCause with @debug.Debug::{to_repr}

///|
/// Typed failure boundaries before an owned child was created.
pub(all) enum StartupFailure {
  Materialization(Error)
  NodeMissing(executable~ : Executable, cause~ : Error)
  ProcessStart(Error)
} derive(Debug)

///|
pub extend StartupFailure with @debug.Debug::{to_repr}

///|
/// Why no child started, including cancellation during materialization.
pub(all) enum StartupStop {
  Failed(StartupFailure)
  Cancelled(CancellationCause)
} derive(Debug)

///|
pub extend StartupStop with @debug.Debug::{to_repr}

///|
/// Observed completion of a started child. The force flag records a request;
/// the status is the actual wait result, independent of inferred cause of death.
pub(all) enum ChildCompletion {
  Exited(ProcessStatus)
  Stopped(cause~ : CancellationCause, status~ : ProcessStatus, force_requested~ : Bool)
  Failed(Error)
} derive(Debug)

///|
pub extend ChildCompletion with @debug.Debug::{to_repr}

///|
/// The factual startup boundary used for application-owned result reporting.
pub(all) enum LaunchResult {
  NotStarted(StartupStop)
  Started(ChildCompletion)
} derive(Debug)

///|
pub extend LaunchResult with @debug.Debug::{to_repr}

///|
/// A protected cleanup or application finalizer failure after child reaping.
pub(all) enum FinalizationFailure {
  PayloadCleanup(Error)
  Finalizer(Error)
} derive(Debug)

///|
pub extend FinalizationFailure with @debug.Debug::{to_repr}

///|
/// Observations made by the driver after cleanup. The selected parent status is
/// separate from child completion because a signal or finalization failure can
/// select a different parent status. The callback receives the selection before
/// its own invocation; a callback failure can still turn success into failure.
pub struct LaunchOutcome {
  priv result : LaunchResult
  priv selected : ProcessStatus
  priv failures : Array[FinalizationFailure]
}

///|
/// Retain typed observations and a separate copy of the failure collection.
pub fn LaunchOutcome::new(
  result : LaunchResult,
  selected : ProcessStatus,
  failures : Array[FinalizationFailure],
) -> LaunchOutcome {
  { result, selected, failures: failures.copy() }
}

///|
/// The observed startup boundary and child completion.
pub fn LaunchOutcome::result(self : LaunchOutcome) -> LaunchResult { self.result }

///|
/// Parent status selected after cleanup and before the completion callback.
pub fn LaunchOutcome::selected_status(self : LaunchOutcome) -> ProcessStatus { self.selected }

///|
/// A fresh collection of protected cleanup and finalizer failures.
pub fn LaunchOutcome::finalization_failures(self : LaunchOutcome) -> Array[FinalizationFailure] {
  self.failures.copy()
}
