# Proposal: Add logging

## Why

A .NET application writes logs through one abstraction,
`Microsoft.Extensions.Logging.ILogger`, and the host chooses the backend. Serilog
adds structured events with message templates, so a log line keeps its values as
data and not only as text. MoonBit has no such abstraction. Each library either
calls `println` or takes a callback of its own shape, and an application cannot
send the logs of all its parts to one place.

finos/morphir-moonbit, the first consumer, flushes its own logs in each command
today. The mediator (`add-mediator`) names "log" as a middleware use, and the host
lifecycle (`add-host-lifecycle`) holds services in a typed record. Both need one
logger type that a library can take and an application can supply. This change
adds the smallest slice that gives that type: one open trait that an application
can implement to bring its own logging backend, structured events with message
templates, and a small set of built-in loggers.

## What Changes

- Add a sixth framework module, `moonrockz/moon-lander-logging` in `pkgs/logging`.
  Its root package (imported as `@logging`) is pure and has the same public API on
  `wasm`, `wasm-gc`, `js`, and `native`. Like `moonrockz/moon-lander-core`, it
  imports no module except `moonbitlang/core`. It sits at the bottom of the
  dependency direction, so config, mediator, hosting, and the umbrella module can
  import it. It is a module of its own, as
  `Microsoft.Extensions.Logging.Abstractions` is a package of its own in .NET: a
  library can depend on the logging abstraction and on nothing else.
- Add six log levels in the order of `Microsoft.Extensions.Logging`: `Trace`,
  `Debug`, `Information`, `Warning`, `Error`, `Critical`.
- Add an immutable log event. It holds the level, an optional category, the
  message template, the named property values, and an optional error.
- Add Serilog-style message templates. A template such as
  `"Loaded {Count} files from {Path}"` binds its positional arguments to named
  properties. The event keeps each value as structured data, and renders the
  message text on request.
- Add one open trait, `Logger`. It is the bring-your-own-logging seam. An
  application or an adapter implements it to send events to any backend. Library
  code takes a `&Logger` value and does not know the backend.
- Add level methods on `&Logger` (`trace`, `debug`, `info`, `warn`, `error`,
  `critical`). Each method checks the level first and builds no event for a
  disabled level.
- Add built-in loggers and combinators: a logger that drops all events, an
  in-memory logger for tests, a minimum-level filter, a fan-out to many loggers,
  and a category wrapper.
- Add a pure text renderer that gives one line for an event.
- Document the package with runnable examples, one of them a bring-your-own
  logger, and add an acceptance suite in the unpublished `tests/` module.

## Capabilities

### New Capabilities

- `logging`: the logger trait as the bring-your-own seam, log levels, structured
  log events, message templates with positional binding, level checks before event
  construction, built-in loggers and combinators, and text rendering, with the
  same behavior on all four targets.

### Modified Capabilities

- `framework-modules`: the module set grows from five to six with
  `moonrockz/moon-lander-logging`; the dependency direction puts it at the bottom
  beside core, with no module import except `moonbitlang/core`; and it shares the
  one framework version.

This change does not change the requirements of `mediator` or of the configuration
capabilities, and it does not depend on the unbuilt `host-lifecycle` capability.

## Impact

- New module `moonrockz/moon-lander-logging` in `pkgs/logging`, a new member of
  `moon.work`, with the root version. No new third-party dependency: the module
  uses only the MoonBit core library, and needs no I/O, no `moonbitlang/async`,
  and no host adapter.
- Module wiring: the framework table of `scripts/validate-packages.mbtx`, the
  framework publish order in `scripts/publish.mbtx`, and the module list in
  `AGENTS.md`. `scripts/versions.mbtx` reads `moon.work`, so it gets the new
  member with no change.
- The module imports no other framework module. No other framework module imports
  it in this change; the dependency direction only permits it.
- Acceptance suites go in the unpublished `tests/` module. Each target leg must
  run more than zero tests for the logging suite.
- finos/morphir-moonbit can implement `Logger` over its own output and pass one
  `&Logger` to each command. That move is a later change in Morphir.

## Out of scope

- Console, standard error, file, or network sinks. These need I/O and go in host
  adapters in a later change. The bring-your-own example shows a one-function
  logger over `println`.
- Configuration of levels from `@config` (the `Logging:LogLevel` section of
  `appsettings.json`), and minimum levels for each category.
- Timestamps. The pure package has no clock. A backend adds the time when it
  receives an event. A later change can add an enricher step that stamps events.
- Enrichers, log context, and scopes (`BeginScope` in .NET, `LogContext` in
  Serilog).
- Event IDs (`EventId` in .NET).
- Template features past named holes and escaped braces: format specifiers
  (`{Elapsed:0.00}`), alignment, destructuring (`{@Order}`), and stringify
  (`{$Order}`) operators.
- A JSON line renderer (for example, the Serilog compact format). The event keeps
  its values as `Json`, so a backend can write JSON itself.
- Async or buffered logging, and background flush.
- A logging middleware for `@mediator` and a logger in the host services record.
  These are later changes after this change and `add-host-lifecycle` land.
- Changes to existing packages to make them write logs.
