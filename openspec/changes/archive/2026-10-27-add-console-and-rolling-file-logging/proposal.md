# Proposal

## Why

Moon-Lander can capture structured log events, but an application must write its
own console and file backends. Add a Literate-style console and rolling files so
the same logger can serve interactive use and retained application logs.

See [proposed output examples](examples.md) for the console, readable rolling
files, and JSON Lines.

## What Changes

- Add a console renderer that distinguishes message text, property values,
  severity, category, time, and errors. Support plain output and controlled ANSI
  color, with standard error as the default destination.
- Support both readable text and JSON Lines in rolling files. The owner selected
  both formats on 2026-10-27. Daily and byte-size rolling can operate together;
  retention is configurable.
- Keep the current synchronous, non-raising `Logger` trait and the pure logging
  root. Add pure formatting under `logging/formatting`, optional runtime sinks
  in a new `moon-lander-logging-hosting-async` module, and a thin lifecycle bridge
  under `hosting/logging`. Verify this split in the first feasibility slice.
- Use a bounded queue and one writer task per session. Expose dropped-event and
  sink-failure reports, explicit drain/close operations, and bounded shutdown.
- Drain after host shutdown and error reporting, before a console driver can end
  the process. Retain existing exit-code and signal precedence.
- Begin with a native/Node/Bun feasibility slice. The pinned async filesystem and
  stdio packages do not implement JS, so the plan includes a narrow extension of
  the existing hosting Node adapter policy after that slice proves it works.

## Capabilities

### New Capabilities

- `logging-sinks`: console output, rolling files, bounded delivery, failure
  reporting, and shutdown of host logging sessions.

### Modified Capabilities

- `logging`: expose immutable message segments for renderers while retaining
  existing template binding, message text, and root-package portability.
- `framework-modules`: register the optional logging runtime module, its dependency
  direction, version alignment, and explicit target-specific adapter packages.

## Impact

The work affects `pkgs/logging`, new `pkgs/logging-hosting-async`, `pkgs/hosting`,
their compiled guides, unpublished acceptance programs, workspace validation,
and the existing adapter build and test tasks. The logging module continues to
import only the MoonBit core library. The optional logging runtime module can depend on
core, logging, and async, but must not depend on configuration or hosting.
Portable contracts and policies remain available on all four targets; process
console and filesystem adapters have explicit native/Node/Bun support. The
implementation adds no package publication or release.

Default rolling policy: UTC day plus 10 MiB, with the newest 31 files retained,
including the active file. File formats share the same delivery and rolling
rules. These are design defaults, not a claim of Serilog compatibility.

## Out of scope

Full Serilog output-template syntax, scopes and enrichers, remote collectors,
configuration-file binding, live reconfiguration, browser filesystem sinks,
multi-process shared-file writing, compression, audit guarantees, and crash-proof
delivery. Existing library code will not acquire a global logger.

## References

- [Serilog console sink](https://github.com/serilog/serilog-sinks-console): Literate
  themes and separation of message values from surrounding text.
- [Serilog file sink](https://github.com/serilog/serilog-sinks-file): combined time
  and size rolling, retention, and text/JSON formatters.
- [Accepted logging design](../archive/2026-10-24-add-logging/design.md): the
  synchronous trait, structured properties, and later host sinks.
