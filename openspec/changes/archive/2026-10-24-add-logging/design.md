# Design: Add logging

Labels: "Owner" marks a decision of the project owner. "Call" marks a
designer decision that the owner did not reject.

## Context

See proposal.md (Why). This section gives only the facts that shape the design.

- The owner asked for logging in the style of .NET
  `Microsoft.Extensions.Logging` (MEL) and Serilog, as the smallest meaningful
  slice, with a trait that lets an application bring its own logging (2026-10-23).
- The MoonBit core library already has a trait named `Logger`. It is the text
  output target of `Show::output(Self, &Logger)`, and
  `pkgs/config` uses it in `Secret::output`. A package that defines its
  own `Logger` shadows the core name inside that package only. Other packages
  see `@logging.Logger` and the core `Logger` as two names.
- Probe with the pinned toolchain (`moon 0.1.20261021`, scratch module outside
  the repo, 2026-10-23), on `wasm`, `wasm-gc`, `js`, and `native`:
  - a `pub(open) trait` with a default for one method compiles, and a type that
    implements only the other method uses the default;
  - `fn &Logger::info(self : &Logger, ...)` adds a method to the trait object,
    and `logger.info(...)` calls it;
  - a wrapper struct that holds a `&Logger` and implements the trait composes;
  - with a parameter type of `Array[Json]`, the call
    `log.info("Loaded {Count} files from {Path}", [3, Json(path)])`
    compiles: the number is a JSON literal and the text goes in `Json(...)`
    (the toolchain deprecates `String::to_json` for `Json(value)`; found in
    group 2);
  - an optional labelled argument `error? : Error` takes any `suberror` value,
    and string interpolation of it gives its `Show` text.
- `@config.Secret` implements `Show` with redaction and does not implement
  `ToJson`. A secret cannot become a property value unless the caller calls
  `expose()` or turns it into text.
- The framework is split into modules (`split-framework-modules`, archived
  2026-10-24). Config and mediator can import only `moonrockz/moon-lander-core`,
  hosting only core and config, and `scripts/validate-packages.mbtx` checks the
  direction from a table of folders, module names, and allowed imports. A type
  that config, mediator, and hosting must all share must sit at the bottom.
- `scripts/versions.mbtx` finds the modules from `moon.work`, so a new member gets
  the version checks with no script change. `scripts/publish.mbtx` holds the
  framework publish order in a comment for the first framework release.
- The mediator (`pkgs/mediator`) and the configuration packages do not log. No
  package in the repo writes logs today.

## Goals / Non-Goals

**Goals:**

- One seam: library code takes `&@logging.Logger`, and the application supplies
  any backend through one trait implementation.
- Structured events. Property values stay data (`Json`) until a backend renders
  them.
- No cost for a disabled level past one level check.
- Pure package with the same API on all four targets, in the `|>` builder style
  of the rest of the framework.

**Non-Goals:**

- No I/O sinks, no clock, no configuration binding, no enrichers or scopes (see
  proposal.md, Out of scope).
- No global or static logger. A logger is always an explicit value.
- No async API.

## Decisions

### D1. One open trait is the bring-your-own seam (Owner: a BYO trait; Call: its shape)

```moonbit
pub(open) trait Logger {
  enabled(Self, Level) -> Bool = _
  log(Self, LogEvent) -> Unit
}

impl Logger with enabled(_self, _level) { true }
```

The trait has one required method, `log`, and one method with a default,
`enabled`. A backend that needs no filter writes one function. The built-in
loggers (D6) implement the same trait, so the application and the framework
use one shape.

`log` returns `Unit` with no `raise` effect. A backend that can fail (for
example, a file write) handles its own error. This matches MEL and Serilog,
where a log call never throws to the caller.

Alternatives considered:

- Two traits, as in .NET: `ILogger` for callers and `ILogEventSink` (Serilog)
  or `ILoggerProvider` (MEL) for backends. Rejected for this slice. One trait
  covers both roles: a backend is a logger, and a combinator is a logger that
  wraps a logger. A separate sink trait can come later without a break, because
  an adapter from a sink to a logger is one wrapper.
- A record of function values (`{ log : (LogEvent) -> Unit, ... }`). Rejected:
  a trait lets a backend keep its own typed state and lets combinators hold
  `&Logger` values, and the probe shows the trait object works on all targets.

The trait is named `Logger`, as in MEL. Inside `@logging` this name shadows the
core `Logger` (see Context). Package code that implements `Show` must not
annotate the parameter of `output` as `&Logger`; it leaves the type to
inference, or writes `&@builtin.Logger`. Callers always see the qualified name
`@logging.Logger`. The alternative name `Log` was considered and rejected: it
reads as a verb and collides with the method name `log`.

### D2. Levels follow MEL (Call)

```moonbit
pub(all) enum Level {
  Trace
  Debug
  Information
  Warning
  Error
  Critical
} derive(Eq, Compare, Show)
```

The constructor order gives the comparison order. MEL names are used, not the
Serilog names (`Verbose`, `Fatal`), because MEL is the abstraction the owner
named first. The MEL value `None` (turn all off) is not a level: the null
logger (D6) has that role, and a level filter has no "off" case to handle.

### D3. The event is an immutable struct with `Json` property values (Call)

```moonbit
pub struct LogEvent {
  level : Level
  category : String?
  template : String
  priv props : Array[(String, Json)]
  error : Error?
}
```

The fields are read-only outside the package. A combinator that changes a
field, such as the category wrapper, makes a new event with a struct update.
The properties are an ordered array, not a map, so the event keeps the hole
order of the template (spec: Message template binding).

A read-only field does not make an `Array` or a `Json` array or object
immutable, so the properties are a private field (review of #91). The bind step
copies each argument deeply, and `LogEvent::properties()` and
`LogEvent::property(name)` give deep copies. A caller that changes an argument
after the call, a reader that changes what it read, and one backend of a
fan-out cannot change the event that another code holds. The cost is one copy
of each value at bind and at each read; the message render reads the private
values without a copy.

Property values are the core `Json` type. Alternatives considered:

- A new enum of value cases. Rejected: `Json` already covers null, booleans,
  numbers, text, arrays, and objects; the core `ToJson` trait and
  `derive(ToJson)` turn an application value into a property with no new code;
  and a backend that writes JSON lines needs no conversion.
- `&Show` values. Rejected: a backend gets only text and loses the structure,
  which is the main reason for Serilog-style events.

Trade-off: a `Json` number is a `Double`, so an `Int64` above 2^53 loses
precision. A caller that needs the exact value passes it as text.

The event holds no timestamp (proposal.md, Out of scope). A backend reads its
own clock when `log` runs.

### D4. Level methods on the trait object (Call)

```moonbit
pub fn &Logger::info(
  self : &Logger,
  template : String,
  args : Array[Json],
  error? : Error,
) -> Unit
```

The same shape exists for `trace`, `debug`, `warn`, `error`, and `critical`,
and a general `write(self, level, template, args, error?)` holds the shared
body. Each method calls `self.enabled(level)` first. Only for an enabled level
does it parse the template, bind the arguments (D5), build the event, and call
`self.log`. The names `warn` and `info` are short forms, as in common
MoonBit and Rust use; the level constructors keep the full MEL names.

`args` has no default. A call with no values passes `[]`. This keeps one
method for each level and no overloads.

Methods on `&Logger`, not free functions such as `@logging.info(log, ...)`:
group 1 compiled both README examples with methods, and `moon info` lists them
as `pub fn &Logger::info(Self, String, Array[Json], error? : Error) -> Unit`
with no `raise` effect. A call reads `logger.info(...)`, as in .NET.

The caller builds the `args` array before the level check runs. The cost of a
disabled call is that array plus one `enabled` call. A caller with an
expensive value checks `logger.enabled(level)` itself first. A lazy argument
form is a later addition, not part of this slice.

### D5. Template parse and render are pure functions (Call)

A template parses into a list of parts: literal text and named holes. The
grammar for this slice:

- `{{` gives a literal `{`, and `}}` gives a literal `}`.
- `{` then one or more name characters (ASCII letters, digits, `_`) then `}`
  is a hole.
- Each other use of a brace is literal text: an unclosed `{`, an empty `{}`,
  a name with other characters, and a single `}`.

Binding takes the holes in order and pairs the first `n` holes with the `n`
arguments. A hole with no argument gives no property. An argument with no hole
is dropped. When one name occurs twice, each hole takes its own argument, and
the event keeps both pairs; the render uses the first value for both holes.
This follows the positional behavior of Serilog. Serilog writes a self-log
note for a mismatch; this package has no self-log, so a mismatch is silent
(spec: Template mismatches do not fail).

`LogEvent::message(self) -> String` parses the template again and renders it
from the properties. The package keeps no parse cache in this slice: a cache
needs mutable shared state, and template parse is linear in the template
length. A later change can add a cache if a benchmark shows a need.

The render rule for values is in the spec (Message rendering): text without
quotes, other values as compact JSON.

### D6. Built-in loggers and combinators (Call)

| Function | Gives | Behavior |
| --- | --- | --- |
| `null_logger()` | `&Logger` | `enabled` gives `false`; `log` does nothing |
| `MemoryLogger::new()` | `MemoryLogger` | Keeps events in an array; `events()` gives a copy |
| `min_level(logger, level)` | `&Logger` | Enables a level at or above `level` and enabled by `logger` |
| `fan_out(loggers)` | `&Logger` | Enables a level if any logger does; sends each event to each logger that enables it |
| `with_category(logger, name)` | `&Logger` | Sets `category` on each event, then passes it on |

The combinators take the logger first so that they chain with `|>`:

```moonbit
let log = backend |> @logging.min_level(Information) |> @logging.with_category("morphir.build")
```

`MemoryLogger` is a public type, not only `&Logger`, so a test can read
`events()`. It is the only built-in logger with mutable state. It is for tests
and examples; the README says so.

Each combinator checks `enabled` again in its own `log`, so an event that
reaches a wrapper by a direct `log` call (not through a level method) still
obeys the filter.

### D7. One text line renderer, no sinks (Call)

`LogEvent::to_line(self) -> String` gives the line of the spec (Text line
rendering): `[INF] category: message`, and a second line `  error: <text>`
when the event has an error. The error text is the `Show` output of the error.
The codes follow the three-letter style of Serilog with the MEL level names.

The package has no console sink. A MoonBit core `println` writes to standard
output on every target, but a command-line application such as Morphir writes
its results to standard output, so a built-in logger there would mix logs with
output. Standard error needs `moonbitlang/async` or a host adapter. The README
shows a bring-your-own logger over `println` in five lines instead, and a
later change adds host sinks.

### D8. A sixth framework module at the bottom (Owner: sixth module, 2026-10-24; Call: the import rule)

The logging abstraction is the module `moonrockz/moon-lander-logging` in
`pkgs/logging`. Its root package holds the whole API of this change, imported as
`@logging`. The module imports no module except `moonbitlang/core`, the same rule
as core, and imports no framework module. Config, mediator, hosting, and the
umbrella module may import it.

The sharing story that this placement serves:

| Part | Users | Needs | Home |
| --- | --- | --- | --- |
| Trait, levels, events, templates, built-in loggers | Config, mediator, hosting, applications, other repos | `moonbitlang/core` | `moon-lander-logging` |
| Console, standard error, and file sinks | Applications through the host | `moonbitlang/async`, adapters | `moon-lander-hosting` (later) |
| Levels from configuration | Host builder | `@config` | `moon-lander-hosting` (later) |
| Logging middleware | Mediator users | Logger and mediator | `moon-lander-mediator` (later) |

The I/O parts go up into hosting, so the logging module stays free of
dependencies. A library outside Moon-Lander (for example, moonrockz/smithy or
finos/morphir-moonbit) can depend on the abstraction and get no configuration,
format, or async module.

Alternatives considered:

- A package in core (`moonrockz/moon-lander-core/logging`). It needs no module
  wiring. Rejected by the owner: core holds shared domain types, and a
  cross-cutting abstraction with its own README and its own consumers outside the
  framework reads better as its own module, as
  `Microsoft.Extensions.Logging.Abstractions` is its own package in .NET.
- A package in the umbrella module (`moonrockz/moon-lander/logging`), the first
  plan. Rejected: config, mediator, and hosting cannot import the umbrella, so the
  framework itself could never log through it.
- Logging imports core. Rejected for this slice: the logging API uses no core
  type. If a later change needs one (for example, `AppName` as a category), that
  change can permit the import.

The root package has no `#cfg` and no per-target file. Tests run through
`mise run test` on all four targets, and a leg that runs zero logging tests is a
failure.

## Risks / Trade-offs

- [The name `Logger` shadows the core trait inside `@logging`] → D1 rule for
  `Show` implementations in the package; the lint and type check catch a wrong
  annotation at compile time.
- [An argument array is built for a disabled level] → D4: document the
  `enabled` check for expensive values; measure before a lazy form is added.
- [Secrets in log values] → The package never formats values that the caller
  did not give. `@config.Secret` has no `ToJson`, so it cannot become a
  property by accident. An error value is rendered through its `Show`
  implementation, and the error type owns redaction. The README warns that a
  caller must not pass `expose()` output to a log method.
- [Precision of large integers in `Json`] → D3 trade-off; pass text when exact
  digits matter.
- [Two templates with the same name twice] → D5 rule keeps both pairs; a test
  fixes the behavior so that it does not change by accident.
- [The single trait is too small for a later sink model] → D1: a sink trait and
  an adapter to `Logger` can come later with no break to callers, because
  callers only see `&Logger`.

## Migration Plan

None. This is a new module. No existing API changes. Rollback is the removal of
the module, its `moon.work` member, its row in the framework table of
`scripts/validate-packages.mbtx`, and its README and `AGENTS.md` mentions.

