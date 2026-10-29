# enclosing-host-controls Specification

## Purpose
Let desktop embedders and enclosing CLI launchers stop a hosted application through
public typed controls while retaining the true stop reason and normal cleanup.

## Requirements

### Requirement: Public embedder stop

A lifetime SHALL expose a synchronous public embedder stop request with an optional
typed exit code. It SHALL enter the existing stop-request path with reason Embedder,
cancel active execution under the normal cancellation contract and retain the
first run-ending reason. The existing requested-stop API SHALL remain compatible.
The final outcome SHALL expose its actual reason through a typed public getter.

#### Scenario: Embedder stops an active command

- **WHEN** an external owner uses a lifetime received through a public hook to request embedder shutdown while its command waits
- **THEN** the command is cancelled, stopping hooks and the final outcome observe Embedder, and the default exit code is zero

#### Scenario: Explicit embedder exit code

- **WHEN** the first stop request is an embedder request with an explicit exit code
- **THEN** the normal exit precedence rules apply to that code without replacing Embedder with Requested

#### Scenario: First reason remains authoritative

- **WHEN** a requested stop or failure precedes an embedder request
- **THEN** the earlier run-ending reason remains and cleanup is not repeated

### Requirement: Embedder shutdown cleanup

An embedder request SHALL use the existing ordered stop phases, cancellation
protection and shutdown budget. Started services SHALL stop once in reverse order.
An explicit embedder request MUST NOT fabricate a signal reason or change the
immutable outcome after shutdown.

#### Scenario: Reverse-order cleanup

- **WHEN** two services have started and an embedder stops the active command
- **THEN** both services complete their normal stop phases once in reverse order, after the command's defers finish

### Requirement: Public typed signal read

A signal probe SHALL expose its synchronous signal read as SignalKind or no value.
The read contract SHALL be cheap and non-raising. It SHALL remain usable by ordinary
hosting runs and by both console drivers without exposing private stop requests.

#### Scenario: Read an enclosing flag

- **WHEN** the enclosing flag changes from no signal to Terminate
- **THEN** reading the public probe returns those values with no conversion through strings or raw exit codes

### Requirement: External console reader

Both console drivers SHALL accept an optional typed signal probe. When supplied,
they SHALL use it for host cancellation checks, late-signal selection and finalizer
exit selection, and SHALL not install their own OS signal listeners or handlers.
The native driver SHALL disable the async runtime's global cancellation signals
without installing a replacement OS handler.

#### Scenario: Synchronous worker cancellation

- **WHEN** an owned JS worker runs a synchronous command that checks cancellation and its parent publishes Interrupt through shared state
- **THEN** the public console path stops that command without a pause, stopping hooks observe Signal(Interrupt), and console selects 130

#### Scenario: Parent termination signal

- **WHEN** the parent publishes Terminate to the worker's public signal probe
- **THEN** stopping hooks observe Signal(Terminate) and console selects 143

#### Scenario: External ownership is retained

- **WHEN** console runs with an enclosing signal reader
- **THEN** it installs no competing console listeners and removes none owned by the enclosing host

### Requirement: Explicit signal ownership

With no external probe, console SHALL retain its current installed-listener and
second-signal immediate-exit behavior. With an external probe, the enclosing owner
SHALL own OS signal delivery and second-signal escalation. Repeated reads of one
sticky signal MUST NOT count as new signals. The API MUST document this boundary.

#### Scenario: Repeated external reads

- **WHEN** cancellation checks and stop hooks read the same external Interrupt value many times
- **THEN** the reads cause one graceful signal stop and do not trigger second-signal termination

#### Scenario: Existing default signal policy

- **WHEN** an unchanged console call receives two handled OS signals during slow shutdown
- **THEN** the existing immediate second-signal exit and code mapping remain unchanged

### Requirement: Per-run signal retention

Console SHALL retain the first observed external signal for the rest of that run,
including shutdown and finalization. A later empty read MUST NOT erase it. A later
change in the level reader MUST NOT fabricate a second signal event; escalation
remains the enclosing owner's responsibility. Separate runs SHALL have separate
observation state.

#### Scenario: Consumed signal stays authoritative

- **WHEN** an external reader returns Interrupt once and then no value
- **THEN** host cancellation and finalization retain that signal and console selects 130

### Requirement: Console finalization with external signals

External signal shutdown SHALL retain the existing error reports, shutdown budget,
once-only finalizer, cancellation-protected draining and exit precedence. A signal
visible during finalization SHALL take signal exit precedence. The supplied probe
SHALL remain the signal source through finalization.

#### Scenario: Finalizer after worker stop

- **WHEN** an external signal stops a worker command and its finalizer performs an async drain
- **THEN** the drain completes once after service cleanup and receives the selected signal exit code

### Requirement: Portable public controls and runtime acceptance

The lifetime request and probe read SHALL build on all four library targets.
Async host and console acceptance SHALL run on native and js as supported by the
existing drivers. Tests SHALL include an actual owned Node worker and unchanged
default signal scenarios, without a downstream or post-hoc stop-reason workaround.

#### Scenario: Public consumer evidence

- **WHEN** acceptance exercises the public embedder API and the parent-worker signal seam
- **THEN** it verifies real hooks, final outcomes and console codes through the framework rather than private test-only stop requests

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
