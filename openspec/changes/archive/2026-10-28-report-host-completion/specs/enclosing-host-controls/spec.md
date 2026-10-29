## ADDED Requirements

### Requirement: Optional application completion reporting
The native and JS console drivers and both logging bridge entry points SHALL accept an optional async completion callback. For each returned RunOutcome, the driver SHALL invoke it once after failure reports and finalization, before process exit. It SHALL receive the real RunOutcome and typed selected ExitCode. Omission SHALL preserve existing behavior. The framework MUST NOT define an application result schema or force skipped command work to run.

#### Scenario: Pending enclosing signal
- **WHEN** an enclosing Interrupt or Terminate is pending before the first hook
- **THEN** no service hook or command runs, and the completion callback can write one application result with selected code 130 or 143

#### Scenario: Completed or failed run
- **WHEN** the run completes, returns a configuration or command failure, stops during startup or cancels a running command
- **THEN** the callback runs once with the actual outcome after the normal cleanup path

#### Scenario: Shutdown deadline
- **WHEN** shutdown times out and skips a stop hook
- **THEN** unconditional logging finalization still drains and closes before the callback runs

### Requirement: Completion preserves finalization and exit precedence
Completion reporting SHALL run protected from cancellation after console finalization. It SHALL observe a closed logging session, including an earlier hosted close. A callback error SHALL change selected success to failure and retain an existing nonzero code. A signal observed during reporting SHALL retain exit precedence. The callback MUST NOT be retried. Its selected code is a snapshot at entry.

#### Scenario: Reporter raises
- **WHEN** the callback raises after a successful or signalled run
- **THEN** finalization has completed once, reporting is not retried, and the process code is 1 for success or retains 130/143 for a signal

#### Scenario: Already closed diagnostics
- **WHEN** a diagnostic service closed the session before telemetry stopped
- **THEN** finalization repeats the idempotent close and the callback observes closed diagnostics with all accepted records accounted for

#### Scenario: Late signal and cancellation
- **WHEN** a signal arrives during the callback or its enclosing task is cancelled
- **THEN** the callback completes under cancellation protection and the selected signal code wins

#### Scenario: Default and embedded consumers
- **WHEN** an existing caller omits the callback or uses the embedded driver
- **THEN** its existing output, cleanup and non-suspending execution contract stay unchanged

### Requirement: Completion preserves pre-run and embedded contracts
Factory and signal-installation exceptions before a returned host outcome SHALL keep their existing raise and cleanup contract. Embedded non-suspending behavior SHALL remain unchanged.

#### Scenario: No outcome exists
- **WHEN** construction or signal installation raises before a host outcome exists
- **THEN** the exception passes out with existing session cleanup and no fabricated completion outcome
