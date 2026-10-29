## ADDED Requirements

### Requirement: Foreign callbacks poll the shared stop request
The hosting package SHALL provide `stop_requested()` on Context, Lifetime and StopToken on all four targets. The method SHALL read the same registered probes and retained stop request as the task-aware checks, without a current-task query. It SHALL retain the existing first reason and signal exit-code rules. Existing `cancelled()` and `check_cancelled()` SHALL retain current-task cancellation semantics.

#### Scenario: A real JS callback reads an idle lifetime
- **WHEN** a Promise callback after setTimeout calls stop_requested during a hosted run before any stop request
- **THEN** the method returns false without a current-coroutine panic

#### Scenario: A foreign callback reads a retained request
- **WHEN** a callback calls stop_application and then polls the same lifetime through its context and token
- **THEN** all stop_requested checks return true and the run keeps the Requested reason

#### Scenario: A callback polls a parent signal without yielding
- **WHEN** a synchronous callback observes a parent-owned signal through a registered probe and calls stop_requested before the watcher can run
- **THEN** the check returns true and retains the signal with its signal exit code

#### Scenario: A later signal preserves the first reason
- **WHEN** a Requested stop precedes a signal and the callback polls again
- **THEN** Requested remains the first reason and the signal exit code takes precedence

#### Scenario: An embedded caller uses the same check
- **WHEN** non-suspending embedded work polls an idle lifetime and then requests stop
- **THEN** context, lifetime and token checks read the same retained request on wasm and wasm-gc

#### Scenario: Task cancellation remains distinct
- **WHEN** a current async task is cancelled without a lifetime request
- **THEN** cancelled reports task cancellation and stop_requested does not invent a lifetime request
