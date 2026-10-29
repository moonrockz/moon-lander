## ADDED Requirements

### Requirement: Enclosing signal ownership through the logging bridge

The public console logging bridge SHALL accept an optional `SignalProbe` on
both entry points and pass it unchanged to the console driver. Omitted probes
SHALL preserve default handlers. Supplied probes SHALL preserve the first true
signal, its `StopReason` and its exit code through hosted cleanup and final drain.
The enclosing owner SHALL retain listener and second-signal ownership.

#### Scenario: Parent-owned non-yielding worker
- **WHEN** the parent receives SIGINT or SIGTERM while a JavaScript worker polls its lifetime without yielding
- **THEN** the logging bridge observes the supplied consuming probe, stops with the actual signal reason, drains accepted records and retains code 130 or 143
- **AND** the bridge installs no competing listeners and removes none of the parent's listeners

#### Scenario: Signal remains authoritative during finalization
- **WHEN** a consuming probe reports a signal and session cleanup runs
- **THEN** later reads and a delivery failure cannot replace the signal exit code

### Requirement: Session-aware hosted diagnostic shutdown

The bridge SHALL provide an additive `run_with_session` entry point whose host
factory receives its actual opaque runtime session. A host service MAY close
that session before later stop hooks. Close SHALL drain previously accepted
records within its limit, accounting for failures. Existing `run` callers SHALL
retain their logger factory and default open-through-stop behavior.

#### Scenario: Diagnostic drain precedes telemetry flush
- **WHEN** telemetry starts before a diagnostic service and the diagnostic stop hook closes the session
- **THEN** diagnostic records accepted before close are written or accounted for before telemetry stops
- **AND** repeated hosted close and bridge finalization do not close resources again

### Requirement: Unconditional session finalization

The bridge SHALL always finalize the same session and report delivery failures,
safely when a hosted service already closed it. Early hosted close SHALL stop
admission. Later log attempts SHALL not reopen the session. Protected cleanup
SHALL remain independent of successful startup and stop hooks.

#### Scenario: Cleanup cannot depend on a successful stop hook
- **WHEN** startup fails, a shutdown deadline skips or times out the diagnostic stop hook, or the bridge is cancelled
- **THEN** unconditional session cleanup still drains accepted records within its own limit and releases resources

#### Scenario: Records after hosted close
- **WHEN** later stopped events, telemetry hooks or failure reports attempt to log after hosted close
- **THEN** the logger rejects those records, counts direct attempts as closed and remains closed
- **AND** default failure diagnostics still reach standard error outside the closed logger
