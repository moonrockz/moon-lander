# logging-sinks Specification

## Purpose
Let host applications send structured events to a readable console and retained
text or JSON Lines files, with bounded delivery and explicit shutdown results.

## Requirements

### Requirement: Portable formatting and host-only I/O

Formatting and rolling decisions SHALL be pure and testable on wasm, wasm-gc,
js, and native. The logging root MUST retain its existing interface guarantees
and core-only dependencies. Console and filesystem I/O MUST stay in explicit
host adapters supported on native and on JS through Node and Bun.

#### Scenario: A library imports only logging

- **WHEN** an isolated consumer imports the logging root
- **THEN** it acquires no async, hosting, configuration, terminal, or filesystem dependency and its existing tests pass on all four targets

#### Scenario: Unsupported browser runtime

- **WHEN** an application runs in a browser or an embedded wasm host
- **THEN** pure rendering remains available and no process console or file sink is installed implicitly

### Requirement: Standalone logging runtime

The optional `moonrockz/moon-lander-logging-hosting-async` module SHALL own runtime
sessions and sinks without importing configuration or hosting. Its root settings
and reports MUST remain portable. `hosting/logging` MUST contain only the host
lifecycle bridge over that lower runtime, with explicit native/js support.

#### Scenario: Standalone sinks do not import the application host

- **WHEN** an isolated native or Node/Bun consumer imports the optional logging runtime
- **THEN** it can use console and file sinks without resolving configuration or hosting modules

#### Scenario: Portable settings and explicit runtime target limits

- **WHEN** consumers compile the optional module root on all four targets and attempt to import its runtime on unsupported targets
- **THEN** settings and report values compile on all four targets, while unsupported runtime imports fail with a target diagnostic instead of providing a silent sink

### Requirement: Typed sink settings

Settings with rules SHALL use private value types and smart constructors with
typed failures. Output paths MUST be absolute and use an explicit base when
resolved from text. Size, retention, queue, and timeout limits MUST be positive.
Rolling policy, format, destination, theme, and color mode MUST be typed cases.

#### Scenario: Invalid limits fail before work starts

- **WHEN** settings contain a zero or negative byte limit, file count, queue capacity, or drain timeout
- **THEN** construction fails with the input and broken rule before any output is opened

#### Scenario: Typed defaults

- **WHEN** an application selects the standard settings
- **THEN** it receives valid typed defaults without parsing magic strings or numeric mode codes

### Requirement: One captured record per accepted event

A session SHALL capture one UTC timestamp and sequence for an accepted event
before it enters the queue. All destinations MUST use that timestamp and event
snapshot. The timestamp MUST record receipt at the session, not the later file
write. Error text MUST be captured before deferred delivery.

#### Scenario: A delayed write retains its timestamp

- **WHEN** an event is accepted just before UTC midnight and the writer drains it after midnight
- **THEN** every destination reports its captured time, while file selection uses the rolling clock rules

#### Scenario: Two destinations observe one record

- **WHEN** one session sends an event to the console and a file
- **THEN** both render the same timestamp, level, category, template, properties, message, and error text

### Requirement: Literate console output

The console SHALL support plain output and a Literate-style theme that
distinguishes literal text, structured values, severity, time, category, and
errors. It MUST retain the existing six level names and codes. Default output
MUST go to standard error; applications MUST be able to select standard output.
Whole events from one session MUST be written in receive order without interleaving.

#### Scenario: Styled values are distinct from text

- **WHEN** a color-enabled console writes an information event with string, number, boolean, and null properties
- **THEN** its output applies the defined value styles without changing the plain rendered message

#### Scenario: Application output stays separate

- **WHEN** a program writes JSON to standard output and uses the default console sink
- **THEN** the JSON stream contains no log record and the logs go to standard error

### Requirement: Explicit console color policy

Color mode SHALL be `Auto`, `Always`, or `Never`. Auto MUST emit ANSI styling
only when the selected destination reports support and is not redirected, the
terminal is not dumb, and `NO_COLOR` is not nonempty. Unknown capability MUST give
plain output. Always MUST explicitly force styling; Never MUST omit it.

#### Scenario: Redirected and unknown terminals stay plain

- **WHEN** Auto is selected and output is redirected or terminal capability is unknown
- **THEN** the output contains no formatter-generated escape sequences

#### Scenario: NO_COLOR and explicit force

- **WHEN** `NO_COLOR` is nonempty
- **THEN** Auto gives plain output, Always gives styled output by explicit request, and Never gives plain output

### Requirement: Log text cannot inject terminal commands

Console and readable file rendering SHALL escape input escape characters and
carriage returns. Newline continuations MUST be visibly indented. Formatter
styling MUST be reset after every styled event. Machine JSON output MUST encode
control characters as JSON data instead of emitting raw control sequences.

#### Scenario: A property contains an ANSI sequence

- **WHEN** a string property contains ESC followed by terminal control text
- **THEN** it appears as escaped text, cannot change terminal state, and is preserved as data when JSON is decoded

### Requirement: Readable and JSON Lines file formats

File sinks SHALL support UTF-8 text and JSON Lines without a BOM or color.
JSON Lines MUST write one object and LF per event, preserving captured time,
level, category, template, message, property values and error text. Schema
version 1 SHALL remain the default and keep all properties in order as an array.
Opt-in version 2 SHALL use named last-wins values and complete per-name history
as defined in object-json-properties.

#### Scenario: Structured values survive JSON output

- **WHEN** a record contains a number, nested object, repeated property name, and newline in error text and uses the default JSON policy
- **THEN** decoding its single JSON line recovers every property in order, including duplicate names, with its original JSON type

#### Scenario: Named JSON output

- **WHEN** a JsonLines sink selects NamedObject
- **THEN** its records use schema version 2 with named last-wins properties and complete duplicate history, without changing captured metadata

#### Scenario: Human-readable file output

- **WHEN** a text file receives a record with category and error
- **THEN** it contains a UTC timestamp, level code, category and message, followed by indented error text without color sequences

### Requirement: Bounded non-raising delivery

The logger receive operation SHALL remain synchronous and non-raising. Admission
MUST bound queued event count and encoded payload bytes, including all selected
destinations and the in-flight record. A full queue MUST discard the newest
incoming record without blocking, record the loss, and continue serving already
accepted records. Oversized records MUST be counted separately.

#### Scenario: A slow writer cannot grow the queue without limit

- **WHEN** the writer is stalled and input exceeds either queue limit
- **THEN** log calls return, existing accepted records keep their order, and each rejected record is counted

#### Scenario: A record exceeds its own limit

- **WHEN** one encoded record exceeds the configured maximum record size
- **THEN** it is rejected and reported as oversized without truncating the record or evicting earlier records

### Requirement: Sink failures are observable and isolated

A failed destination SHALL report a typed failure with its operation and target
without raising from a log call or logging recursively. A destination write failure
MUST stop further writes to that destination for the session; other destinations
MUST continue. Partially failed writes MUST NOT be retried automatically as if
no bytes had been written. Status reads MUST be immutable snapshots.

#### Scenario: File output fails but console output survives

- **WHEN** a file write fails after the session starts
- **THEN** the failure and unwritten records are reported, console delivery continues, and later log calls do not raise

#### Scenario: Retention deletion fails

- **WHEN** the writer cannot delete an old owned file
- **THEN** it reports that retention failure, keeps the successfully opened active file, and does not discard the current event

### Requirement: Combined time and size rolling

Files SHALL roll on UTC day, byte size, or both. The default MUST be both, with a
10 MiB limit. File selection MUST use a nondecreasing writer period even if the
wall clock moves backward. A nonempty file MUST roll before a record would exceed
the size limit. An empty file MUST accept one whole oversized record, within the
separate record limit, without an infinite rolling loop.

#### Scenario: One day has several size rolls

- **WHEN** the records of one UTC day exceed the configured file limit
- **THEN** they are written in order to successively numbered files without splitting a record across files

#### Scenario: The first event of the next day

- **WHEN** time rolling is enabled and a write occurs in a later UTC day
- **THEN** it selects a new day's file before writing, independent of daylight-saving changes

#### Scenario: A backward clock does not reopen an older period

- **WHEN** the writer has advanced to day 28 and the clock moves back to day 27
- **THEN** subsequent writes remain in the current period until a later period is observed

#### Scenario: Record larger than the file limit

- **WHEN** an accepted record exceeds the file limit but fits the record limit
- **THEN** it is written whole to one file and the following record rolls away from that oversized file

### Requirement: Exclusive ownership and restart behavior

A file set SHALL have one writer. A second session or process for that set MUST
fail visibly before writing or retention. A normal restart MUST inspect existing
owned files, append or advance by policy, and never truncate them. File resources
MUST remain unopened until the first event directed to that file set.

#### Scenario: Restart after a clean close

- **WHEN** a writer closes cleanly and a new session opens the same file set
- **THEN** the new writer retains the existing contents and continues the appropriate sequence

#### Scenario: Concurrent owner or stale ownership marker

- **WHEN** the file set's exclusive ownership marker exists
- **THEN** a new writer reports ownership unavailable and does not remove the marker automatically or modify the files

#### Scenario: No event means no file output

- **WHEN** a session runs and closes without a file-directed event
- **THEN** it creates no log directory, log file, or ownership marker

### Requirement: Retention touches only the owned file set

Retention SHALL keep the newest configured count of files, including the active
file, or keep all files by explicit selection. The default MUST be 31. Cleanup
MUST run only after a replacement file opens successfully. It MUST match the
exact owned naming scheme and MUST NOT delete unrelated files, directories,
symbolic links, or the active file.

#### Scenario: Another file resembles a log

- **WHEN** the log directory contains owned rolls and unrelated files with a similar prefix
- **THEN** cleanup removes only old regular files that match the complete owned scheme

#### Scenario: A new roll cannot open

- **WHEN** opening a replacement file fails
- **THEN** retention does not delete older files to try to make the failed roll appear successful

### Requirement: Explicit drain and close

A session SHALL expose async drain and idempotent close operations with bounded
completion and a report of writes, drops, and failures. Drain MUST cover the
records accepted before its sequence barrier. Close MUST stop admission, drain
accepted records, and close owned resources. Completion MUST mean writes reached
the OS or stream callback, not crash-proof durable storage.

#### Scenario: Producers continue during drain

- **WHEN** a drain starts and other producers later enqueue records
- **THEN** drain waits for its captured barrier rather than waiting forever for a permanently empty queue

#### Scenario: Repeated close and writes after close

- **WHEN** close is called twice and a caller then invokes the receive operation with an existing event
- **THEN** resources close once, the report remains available, the late event is counted as rejected without raising, and level methods see the closed logger as disabled

### Requirement: Host logs drain before process exit

Opt-in host logging SHALL remain active through service shutdown, stopped
callbacks, and final host error reporting, then drain before the console driver
returns or exits. Final drain MUST be bounded and protected from the first
cancellation. A second signal or forced termination retains immediate-exit
behavior and carries no delivery guarantee.

#### Scenario: Shutdown hook and final report are logged

- **WHEN** a hosted program logs from stop hooks and a stopped callback, reports a command failure, and shuts down normally or on its first signal
- **THEN** the accepted records and final report complete before native exit or JS driver completion, within the drain bound

#### Scenario: Drain failure preserves the primary exit reason

- **WHEN** closing logs fails after the application has selected a usage, command, or signal exit code
- **THEN** the existing exit-code precedence is preserved, while a drain failure after an otherwise successful run gives exit code 1

#### Scenario: Cancellation or timeout before service startup

- **WHEN** a run is cancelled or fails before start hooks finish, or service shutdown times out
- **THEN** the logging finalizer is still attempted once and is not skipped with the remaining service hooks

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
