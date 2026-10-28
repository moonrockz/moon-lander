# Design

## Context

See [the proposal](proposal.md) for scope and references. The current root logger
is synchronous, non-raising, and pure. Events keep structured properties but have
no timestamp. The template parser is private; rendering color from an already
flattened message would lose the distinction between text and bound values.

The accepted module rules prohibit all non-core dependencies in the logging
module, not only imports at its root. Hosting is permitted to import logging,
config, and core, and already uses `moonbitlang/async@0.22.5`. In that pin, `async/fs` and
`async/stdio` do not implement JS. Existing hosting Node adapters already write
standard error through a completed stream callback.

The native console driver calls libc `exit` after `@hosting.run`. A surrounding
`defer` or an early `stopping` hook cannot guarantee the final logs are drained.
The host can also skip remaining service hooks after a shutdown timeout.

## Goals / Non-Goals

Keep library logging independent of output, and make host delivery bounded,
observable, and testable without real time or a real terminal. Build one common
rendering and rolling policy for native, Node, and Bun.

Do not add an async operation to `Logger`, a global logger, or a
browser/embedded filesystem sink. Do not promise Serilog syntax,
Compact JSON/CLEF interoperability, crash durability, or multi-process sharing.

## Decisions

### D1. Separate portable logging from optional host delivery (Call)

The owner permits new packaging combinations to preserve target support,
including `logging-abstractions`, `logging-async`, and `logging-hosting-async`.
Compare these at the module boundary because dependencies are declared in
`moon.mod`; moving async code to a subpackage of the current logging module
would still violate its core-only dependency rule.

| Option | Consequence | Decision |
| --- | --- | --- |
| All runtime sinks under `hosting/logging` | Reuses the current module set, but standalone sinks resolve hosting and configuration | Replace the initial proposal |
| Rename the base module to `logging-abstractions` | Separates contracts explicitly, but moves existing imports or needs a compatibility module | Keep the existing base name and imports |
| Base logging plus `logging-async` | Suitable for an independent async pipeline, but does not identify the process/filesystem dependency | Revisit if a separately consumed async pipeline is needed |
| Base logging plus `logging-hosting-async` | Identifies async process/file delivery and keeps it independent of the application host | Preferred split, subject to the first consumer proof |

The new name follows the existing `hosting` convention. The module owns runtime
I/O for logging and does not import `moon-lander-hosting`. Do not introduce all three new modules speculatively.
If the first slice shows another split is necessary, revise these requirements
before building later groups.

| Package | Responsibility | Targets |
| --- | --- | --- |
| `logging` | Existing trait/events; add immutable message segments | all four |
| `logging/formatting` | Captured timestamp values, text/JSON rendering, semantic styles | all four |
| `logging/rolling` | Typed file-set names, period/sequence selection, size and retention decisions | all four |
| `logging-hosting-async` | Pure typed session settings and report values | all four |
| `logging-hosting-async/runtime` | Session, admission, writer task, drain and native/Node adapters | native and js |
| `hosting/logging` | Opt-in host lifecycle and pre-exit integration using the runtime session | native and js |

The two pure subpackages use only core and packages of their own module.
The new module may import core, logging, and async, but no configuration, mediator,
or hosting module. Hosting may import the new module; the umbrella may also import
it. Config and mediator retain their existing dependency limits. Leave the
current logging module core-only and keep its public imports stable.

Filesystem paths stay in the new logging runtime module. A private `LogDirectory` consumes
`@core.AbsolutePath` and checks only additional I/O rules, such as rejecting NUL;
it does not repeat absolute-path parsing. Relative input must first use an
explicit base at the application boundary. A rolling decision carries owned file
names, not raw OS paths. No config import is needed for sink settings.

All portable packages, including the new module root, must build and test on
wasm, wasm-gc, js, and native. The runtime and lifecycle bridge are explicit host
adapter packages with declared native/js targets and documented reasons. Do not
add dummy filesystem implementations on unsupported targets. The existing
bring-your-own `Logger` remains available there. A dependency on the optional
module does not promise filesystem support in a browser or embedded wasm host.

Register the module in `moon.work`, the dependency validator and its tests, and
the shared version checks. Update the module-layout documentation, agent rules,
and prospective publication order. Keep actual release publication limited to
the currently authorized modules. Isolated consumers must prove that logging
alone resolves no async dependency and that standalone sinks resolve neither
hosting nor configuration. Compile portable packages on all four targets and
check that unsupported imports fail clearly rather than silently discarding logs.

### D2. Prove the adapter boundary first (Call)

The first group is a vertical feasibility slice: an application writes one event
through the existing trait, an async worker writes it to a console stream and an
appended file, and close completes before a child exits. Run on native and JS
under Node/Bun on Linux, macOS, and Windows. Capture Unicode and pipe output.

Use `moonbitlang/async` for native filesystem/process work and orchestration. For
JS, prove a small `pkgs/logging-hosting-async/adapters/node/` boundary over Node stream
and filesystem APIs, bundled by the existing pinned Bun/MoonBit task. Reuse the
adapter result/error style and test ESM as well as ordinary runtime output.
After the proof, propose the exact narrow extension to the Node adapter
exception in AGENTS.md in that group's PR; do not broaden it to general Node I/O.
No production JS sink lands without that recorded exception and working tests.
The same slice must prove the module/root/runtime target split and both isolated
consumer dependency graphs before later groups depend on the package layout.

Terminal capability detection is a separate boundary input. Use a public
supported native API if the spike finds one; otherwise native Auto conservatively
reports Unknown and an application can explicitly choose Always. Node uses the
selected stream's `isTTY` and terminal/environment hints. Do not introduce a new
C stub or turn on Windows console modes merely to obtain automatic colors.
The spike records the native Auto limitation if it remains.

Feasibility result: the split, both isolated consumer graphs, the console driver
finalizer and one event through console, appended file, drain and exit work on
native and on js under Node and Bun, so the package layout stands. The pinned
`moonbitlang/async@0.22.5` has no js `fs` or `stdio` and no public terminal check.
The js adapter therefore covers exactly stream writes with the write callback,
`isTTY`/`hasColors()`, recursive `mkdir`, exclusive create (`wx`), append open,
complete writes, close, `readdir`, `lstat` and `unlink`; AGENTS.md records this
exception. Native Auto colors report Unknown and stay plain.

### D3. Capture once; preserve the synchronous trait (Call)

One session owns a logger implementing the existing trait, one bounded admission
queue, and one async writer task. It captures a validated UTC timestamp from an
injected clock and a private sequence, then freezes error text and renders the
payloads before admission. The production clock is read in the host boundary;
pure tests supply time. `@async.now()` uses epoch milliseconds in the current pin.

The logger does not await, open files, spawn per-event tasks, or perform writes.
Use private mutable state with immutable status/report snapshots. Cooperative
tasks share a session in one async runtime; cross-thread sharing is out of scope.
One record is admitted to all selected destinations together. Per-destination
minimum levels select which payloads are needed before their rendering.

### D4. Rendering uses semantic segments (Call)

See [proposed output examples](examples.md) for representative output and a
Literate styling breakdown.

Expose literal and bound-value message segments from `LogEvent`, with defensive
copies as for `properties()`. This reuses the existing parser and first-binding
rules instead of maintaining a second template parser in a sink.

`LogTimestamp` is a private validated epoch-millisecond value with a supported
UTC calendar range; conversion and formatting are pure core-only code. Test leap
years, epoch boundaries, and both limits. UTC is the first version's only zone.

Defaults:

- Console: `[12:34:56.789Z INF] category: message`, category omitted when absent.
- Text files: `2026-10-27T12:34:56.789Z [INF] category: message`.
- Error and message continuation lines have a visible indent.
- Literate theme uses muted metadata/literals, distinct value styles, and level
  emphasis. Support `Literate` and `Plain` (no styles); a programmable theme API
  can follow.
- Colors are ANSI, controlled by `Auto | Always | Never`. Auto respects nonempty
  `NO_COLOR`, `TERM=dumb`, redirection, and Unknown capability. Always is an
  explicit override. Default destination is stderr, with stdout opt-in.
- Escape caller-supplied ESC and CR before any console/text styling. Only the
  formatter can emit styling codes; reset its style after each event.

File format is `Text | JsonLines`, with Text as the default. Applications can add
two file destinations to obtain both. JSON has `schemaVersion: 1`, UTC `timestamp`,
the existing `level` name, nullable `category`, `messageTemplate`, `message`,
`properties`, and nullable `error`. Properties are an ordered array of
`{name, value}` objects. This keeps repeated names and every JSON value; a JSON
object keyed by property name would silently lose duplicate bindings. Do not
claim compatibility with Serilog's different JSON schemas.

### D5. Bounded admission and explicit failures (Call)

Use private positive value types for `QueueEventLimit`, `QueueByteLimit`,
`RecordByteLimit`, `FileByteLimit`, `RetainedFileCount`, and a typed drain time
limit. Defaults are 1024 outstanding records, 8 MiB outstanding payload, 1 MiB
per record, and a 5-second final drain. Encoded bytes include all destinations and
the in-flight record. This bounds retained payload; encoding a caller's single
large input can still need temporary memory before it is rejected.

`LogFileStem` accepts one ASCII letter followed by ASCII letters, digits, `_`, or
`-`, at most 64 characters, and rejects the reserved Windows device names
(`CON`, `PRN`, `AUX`, `NUL`, `COM0`-`COM9`, `LPT0`-`LPT9`) without regard to case.
It also rejects a stem that ends with `_` or `-` and digits, so the generated
names of two valid stems never collide (`acme_001` would equal the second file of
`acme`). This
gives generated names the same rules on each OS. An absolute log-directory
constructor consumes the already parsed path and checks only the extra absolute
rule; it does not repeat its separator/root parsing. All these types have private
fields, typed failures, and valid default constructors or constants.

Discard newest on overflow. Count queue-full, oversized, closed, and reentrant
receive attempts separately. Do not disable a level merely because the queue is
full, because that would hide drops behind the level check. Closed sessions do
disable levels; direct receives after close are counted but never raise.

Report typed failures by operation and target, with counters and an optional
non-raising observer outside the logging pipeline. Guard observer reentrancy.
Retain aggregate counters and the latest failure per destination, not an
ever-growing list of dropped events or retention errors.
A failed write disables that destination for the session and accounts for its
undelivered records. Other destinations continue. Do not automatically replay
an ambiguously partial write. Retention failure is separately reported and does
not disable a healthy output file. Setup validates settings; lazy open errors
are reported by the worker and final drain result.

### D6. Rolling and retention are a pure state machine (Call)

`RollingPolicy` is `Daily | Size(FileByteLimit) | DailyAndSize(FileByteLimit)`.
Default is DailyAndSize with 10 MiB. UTC periods avoid local-time and DST
ambiguity. Use writer time for file selection and captured receipt time inside
records. Clamp the writer period to the last opened period on clock rollback.

For stem `acme`, daily text files are `acme-20261027.log`, then
`acme-20261027_001.log`. Size-only starts at `acme.log`, then `acme_001.log`.
JSON files use `.jsonl`. Sequence numbers have at least three digits and can
grow; overflow is a typed failure rather than filename reuse. A move to a later
UTC day reads the directory as a restart does, so a file that an earlier run
left for that day is appended to when it has room, and else the next sequence
opens. Byte counts are a `ByteCount` value, parsed once at the adapter. The pure policy
returns an action plan; the adapter confirms I/O results before state advances.

Count actual encoded bytes, including newline and error continuations, plus the
existing file length after reopen. Roll a nonempty file before the next record
would exceed the limit. Write a record larger than the file limit whole into an
empty file, then roll before the next record. Never split a record across rolls.
A partial OS write failure can leave a partial tail; report it and disable that
destination, without claiming an audit or crash-recovery guarantee.

The host lazily creates directories and acquires an exclusive-create ownership
marker on the first file-directed event. The marker is per directory/stem/format
file set; one namespace must not mix rolling policies. Remove the owned marker
only after normal close. An existing marker, including one left after a crash,
fails visibly; no PID guess or automatic stale-marker removal. Document recovery
after confirming no writer is active. The spike must prove exclusive creation
and handle cleanup on all runtime/OS combinations.

Use `Retention::KeepNewest(RetainedFileCount) | KeepAll`, default KeepNewest(31),
including the active file. Parse complete filenames for the owned set and sort
by period/sequence, not mtime or a broad prefix. Delete only old regular files
after the new file has opened. Ignore links, directories, markers, and similar
names. Keep file sets isolated when two formats or stems share a directory.
Prove restart, byte accounting, and deletion failures with injected directory
and file answers, then test the actual adapters in temporary directories.

### D7. Drain at the process-exit boundary (Call)

Drain captures an accepted-sequence barrier. It completes after every applicable
destination has written or accounted for those records. Later producer activity
cannot starve it. Close stops admission, drains, closes once, and returns a typed
report. Completed writes mean OS acceptance or the Node stream callback; fsync
durability and audit delivery are outside this change.

Standalone applications run the writer inside a scoped async session. Host
integration additionally uses an explicit console-driver finalization boundary
after `@hosting.run` and its error reports, before libc exit or JS exit handling:
`@console.run(host, command, finalize?)`, where a `Finalizer` gets the selected
exit code and gives the final one. The host gains `@hosting.report_writer`, which
sends the default report lines to the bridge instead of standard error.
It must also run when configuration or service startup fails. Do not implement
this only as a hosted stopping/stopped hook: those can run too early or be skipped.
The opt-in integration bridges the default host error report into the session;
an explicitly supplied application report keeps its behavior and can also write
through that logger. Both complete before the final drain.
The feasibility slice compiles the callback/API shape before later groups rely
on it. Existing console users without logging retain their behavior.

Final drain is protected from the first cancellation, with its own 5-second
budget after host shutdown. After a drain timeout, close gives the cancelled
writer and the file closes at most 1 second, and the direct failure report at
most 1 second; document the total bound as host shutdown plus log drain plus
2 seconds. A second signal still exits immediately. A failed drain after success
selects code 1; existing command, usage, shutdown, and signal precedence otherwise
remains. Report final sink failures through the direct diagnostic boundary,
never through the failed logger. No logging is done in a signal handler.

### D8. Deliver in six vertical slices (Call)

Use the groups in `tasks.md`. Each group includes its tests, documentation, and
public interface update. The first group proves uncertain runtime and shutdown
behavior before the full API is built. Existing Linux/macOS/Windows jobs run real
executables; pure policy tests run on every target. No native toolchain pin or
cross-build plan change is needed. If implementation changes those, follow the
repository's zig-cross doctor requirements at that point.

## Risks / Trade-offs

- Synchronous logging cannot wait for a full queue. Visible drops are preferable
  to an unbounded queue or a hidden change to the trait; this is not an audit sink.
- Default native Auto colors may be unavailable through the pinned public APIs.
  Report Unknown and stay plain; explicit Always still enables Literate output.
- A stalled console blocks this session's writer from advancing to files. Bound
  drain and report the destination failure; independent sessions can be used when
  an application needs independent scheduling.
- Exclusive markers can remain after a crash. Fail closed and document manual
  recovery; shared writers and automatic stale-lock recovery need a later design.
- UTC and fixed layout omit some Serilog customization. They keep rolling and
  byte expectations deterministic without altering message-template semantics.

## Migration and workflow

This is opt-in. Existing loggers and `to_line()` keep their behavior. Register no
sink automatically and add no configuration-file schema in this change.

After plan approval, create one beads epic and one story per numbered task group,
record their IDs in `tasks.md`, and connect the stated dependencies. The final
implementation PR archives the change. Close and sync the stories after their
PRs merge. No release or package publication is part of this work.
