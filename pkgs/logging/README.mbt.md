# moonrockz/moon-lander-logging

Structured logging for the Moon-Lander framework, in the style of .NET
`Microsoft.Extensions.Logging` and Serilog. Library code writes events through one
trait, `Logger`, and the application brings the backend that receives them. The
module imports nothing except the MoonBit core library, so a library can depend on
the logging abstraction and on nothing else. It has the same API on `wasm`,
`wasm-gc`, `js` and `native`, and does no I/O.

Import the root package with an explicit alias, because the module name has `-`
in it:

```moonbit notest
///|
import {
  "moonrockz/moon-lander-logging" @logging,
}
```

## The parts

| Part | What it is |
| --- | --- |
| `Logger` | The trait that a backend implements. `log` gets each event; `enabled` filters levels and enables each level by default |
| `Level` | `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`, from the lowest to the highest |
| `LogEvent` | One immutable event: level, category, template, properties and error |
| Level methods | `trace`, `debug`, `info`, `warn`, `error` and `critical` on a `&Logger` |
| `MemoryLogger` | A logger that keeps each event, for tests and examples |

## Bring your own logger

A backend is one type with one function. This one prints each event with
`println`. A real backend can write to standard error, a file or a service; the
pure module leaves that I/O to the application or the host:

```mbt check
///|
struct PrintLogger {}

///|
impl @logging.Logger for PrintLogger with log(_self, event) {
  println(event.to_line())
}

///|
test "bring your own logger" {
  let logger : &@logging.Logger = PrintLogger::{  }
  logger.info("Build started for {Target}", ["wasm"])
}
```

This prints `[INF] Build started for wasm`. `to_line` gives the three-letter
level code (`TRC`, `DBG`, `INF`, `WRN`, `ERR` or `CRT`), the category and a colon
when the event has one, and the message text. An error goes on a second line as
`  error: <text>`, with the `Show` text of the error.

Library code takes a `&Logger` and does not know the backend. A test gives it a
`MemoryLogger` and reads the events back:

```mbt check
///|
fn build(logger : &@logging.Logger) -> Unit {
  logger.info("Build started", [])
  logger.warn("Cache is empty", [])
}

///|
test "read the events of a library function" {
  let memory = @logging.MemoryLogger::new()
  build(memory)
  let levels = memory.events().map(event => event.level)
  assert_eq(levels, [Information, Warning])
}
```

## Message templates

A message template names its values, as in Serilog. The arguments bind to the
holes in order, and the event keeps each value as `Json` data, not as text. A
backend can write the properties as fields, and `message` renders the text when a
backend wants it:

```mbt check
///|
test "a template keeps its values as data" {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = memory
  let path = "src"
  logger.info("Loaded {Count} files from {Path}", [3, Json(path)])
  let event = memory.events()[0]
  assert_eq(event.template, "Loaded {Count} files from {Path}")
  assert_eq(event.properties(), [("Count", 3), ("Path", "src")])
  assert_eq(event.message(), "Loaded 3 files from src")
}
```

A literal is a `Json` value as it is; another value goes in `Json(value)`. A type
with `derive(ToJson)` becomes a JSON object, so its fields stay separate.

| Template part | Meaning |
| --- | --- |
| `{Name}` | A hole. The name holds ASCII letters, digits and `_` |
| `{{` and `}}` | A literal `{` and a literal `}` |
| Any other brace | Literal text, for example an unclosed `{Name` or an empty `{}` |

In the message text, a JSON string shows without quotes, and each other value
shows as compact JSON, for example `{"id":1}`. A mismatch never fails and never
drops the event:

| Case | Result |
| --- | --- |
| A hole has no argument | No property; the message keeps the hole text, for example `{Target}` |
| An argument has no hole | The argument is dropped |
| One name in two holes | Each hole takes its own argument; the message shows the first value in both |

## Built-in loggers and combinators

| Function | Result |
| --- | --- |
| `null_logger()` | Enables no level and drops each event |
| `MemoryLogger::new()` | Keeps each event; `events()` gives a copy |
| `min_level(logger, level)` | Passes only the events at `level` or higher that `logger` enables |
| `fan_out(loggers)` | Gives each event to each logger in the list that enables its level |
| `with_category(logger, name)` | Sets the category `name` on each event |

Each combinator takes the logger first, so a chain reads from the backend to the
code that writes:

```mbt check
///|
test "chain the combinators" {
  let memory = @logging.MemoryLogger::new()
  let logger = memory
    |> @logging.min_level(Information)
    |> @logging.with_category("morphir.build")
  logger.debug("Dropped", [])
  logger.info("Loaded {Count} files", [3])
  let events = memory.events()
  assert_eq(events.length(), 1)
  assert_eq(events[0].category, Some("morphir.build"))
}
```

`fan_out` sends one event to two backends, each with its own level:

```mbt check
///|
test "two backends with their own levels" {
  let console = @logging.MemoryLogger::new()
  let errors = @logging.MemoryLogger::new()
  let logger = @logging.fan_out([console, @logging.min_level(errors, Error)])
  logger.warn("Disk {Name} is low", ["C"])
  assert_eq(console.events().length(), 1)
  assert_eq(errors.events().length(), 0)
}
```

## Levels and the level check

Each level method asks the logger `enabled` before it builds an event. A backend
that implements `enabled` pays only that one call for a level it does not want:

```mbt check
///|
struct WarningsOnly {
  mut written : Int
}

///|
impl @logging.Logger for WarningsOnly with enabled(_self, level) {
  level >= Warning
}

///|
impl @logging.Logger for WarningsOnly with log(self, _event) {
  self.written += 1
}

///|
test "a disabled level builds no event" {
  let backend = WarningsOnly::{ written: 0 }
  let logger : &@logging.Logger = backend
  logger.debug("Not built", [])
  logger.error("Built", [])
  assert_eq(backend.written, 1)
}
```

A log call never fails the code that writes it: `log` has no error effect, and a
backend that can fail handles its own failure.

## Secrets

The module writes only the values that a caller gives it. A configuration
`Secret` has no `ToJson`, so it cannot become a property by accident, and its
`Show` text is redacted. Do not give the text of `Secret::expose` to a log
method: the event keeps it, and each backend can write it. An error goes into a
line through its `Show` text, so the error type decides what the line holds.
