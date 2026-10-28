# Log formatting

The `formatting` package (`@formatting`) renders log events as text for a
console, for a readable log file and for JSON Lines. It is pure: it does no I/O
and reads no clock. It has the same API on `wasm`, `wasm-gc`, `js` and `native`,
and imports only the MoonBit core library and the logging root. A sink or a host
adapter writes the text that it gives.

```moonbit notest
///|
import {
  "moonrockz/moon-lander-logging" @logging,
  "moonrockz/moon-lander-logging/formatting",
}
```

## The parts

| Part | What it is |
| --- | --- |
| `LogTimestamp` | A UTC time in milliseconds, from 1970-01-01T00:00:00.000Z to 9999-12-31T23:59:59.999Z |
| `LogRecord` | One captured event and its time. It does not change after `capture` |
| `Theme` | `Literate` (ANSI colors) or `Plain` (no ANSI codes) |
| `format_console` | One console event, for example `[14:23:07.012Z INF] app: Started` |
| `format_text` | One event of a readable log file, with the full UTC date |
| `format_json_line` | One JSON Lines record of schema version 1 |
| `utf8_length` | The UTF-8 bytes of a rendered record, for size limits |

## Capture a record

A session captures each event one time, with the time at which it got the event.
`capture` reads the message, the segments, the properties and the `Show` text of
the error now, so each sink renders the same values:

```mbt check
///|
test "capture an event with its time" {
  let memory = @logging.MemoryLogger::new()
  @logging.with_category(memory, "workspace.loader").info(
    "Loaded {Count} files from {Path}",
    [3, "src"],
  )
  let time = @formatting.LogTimestamp::from_epoch_millis(1793110987024L)
  let record = @formatting.LogRecord::capture(memory.events()[0], time)
  assert_eq(record.message(), "Loaded 3 files from src")
  assert_eq(record.timestamp().to_iso8601(), "2026-10-27T14:23:07.024Z")
  assert_eq(record.timestamp().time_of_day(), "14:23:07.024Z")
  assert_eq(record.timestamp().compact_date(), "20261027")
}
```

`LogTimestamp::from_epoch_millis` raises `TimestampOutOfRange` for a time out of
the range. The range gives each time a four-digit year, so the text forms have
one length and sort in time order. UTC is the only zone.

## Console and readable files

The two text layouts have fixed parts. The category and its `: ` are not there
when the event has no category:

| Layout | Example |
| --- | --- |
| Console | `[14:23:07.012Z INF] workspace.loader: Loaded 3 files from src` |
| Readable file | `2026-10-27T14:23:07.024Z [INF] workspace.loader: Loaded 3 files from src` |

The level codes are `TRC`, `DBG`, `INF`, `WRN`, `ERR` and `CRT`, as in
`LogEvent::to_line`. Each line of the error text, and each continuation line of
a message with a line break, starts with four spaces. Each rendered event ends
with one LF:

```mbt check
///|
suberror BuildError {
  BuildError(String)
}

///|
impl Show for BuildError with output(self, logger) {
  let BuildError(text) = self
  logger.write_string(text)
}

///|
test "readable text with an error" {
  let memory = @logging.MemoryLogger::new()
  @logging.with_category(memory, "build.compiler").error(
    "Compilation failed for {File}",
    ["app.mbt"],
    error=BuildError(
      "CompilerError: Unknown identifier calculate_total\n  at app.mbt:42",
    ),
  )
  let time = @formatting.LogTimestamp::from_epoch_millis(1793110987041L)
  let record = @formatting.LogRecord::capture(memory.events()[0], time)
  inspect(@formatting.format_text(record), content=(
    #|2026-10-27T14:23:07.041Z [ERR] build.compiler: Compilation failed for app.mbt
    #|    CompilerError: Unknown identifier calculate_total
    #|      at app.mbt:42
    #|
  ))
  inspect(@formatting.format_console(record, Plain), content=(
    #|[14:23:07.041Z ERR] build.compiler: Compilation failed for app.mbt
    #|    CompilerError: Unknown identifier calculate_total
    #|      at app.mbt:42
    #|
  ))
}
```

### Control characters

Caller text can hold control characters. Before it adds a style, the renderer
replaces each of these characters in the category, the message and the error
text with the visible text `\xNN`, with two lower-case hex digits:

- Each C0 control character (U+0000 to U+001F) except LF and TAB. For example
  ESC is `\x1b` and CR is `\x0d`.
- DEL (U+007F).
- Each C1 control character (U+0080 to U+009F), which includes the one-byte CSI.

So a value cannot send a command to a terminal, and only the renderer writes
ANSI codes. A CR LF line end shows `\x0d` before the line break. A literal
backslash in caller text stays as it is, so the text `\x1b` can also come from
the caller.

```mbt check
///|
test "an escape character becomes visible text" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).warn("Input {Value}", ["\u{1b}[2Jcleared\r"])
  let record = @formatting.LogRecord::capture(
    memory.events()[0],
    @formatting.LogTimestamp::earliest(),
  )
  inspect(@formatting.format_console(record, Plain), content=(
    #|[00:00:00.000Z WRN] Input \x1b[2Jcleared\x0d
    #|
  ))
}
```

### Themes

`Plain` writes no ESC character. `Literate` adds ANSI SGR styles and keeps the
same text: when you remove the styles from `Literate` output, you get the `Plain`
output. Each styled part ends with a reset (`ESC [0m`), so no style continues past
a line end or past the event.

| Part | `Literate` style |
| --- | --- |
| Time, brackets and category | Bright black (`90`) |
| Literal message text | White (`37`) |
| Number value | Bright magenta (`95`) |
| String value | Bright cyan (`96`) |
| Boolean value | Bright blue (`94`) |
| Null value | Blue (`34`) |
| Array or object value | Bright green (`92`) |
| `TRC` / `DBG` / `INF` | Bright black / white / bright white |
| `WRN` | Bright yellow (`93`) |
| `ERR` / `CRT` | Bright white on red (`97;41`); `CRT` is also bold |
| Error text | Bright red (`91`) |

The style of a value comes from its JSON type, not from the words of the
message. A string value has no quotes, as in `LogEvent::message`. The renderer
does not decide if a stream supports colors. The console sink selects the theme
from its color mode (`Auto`, `Always` or `Never`).

```mbt check
///|
test "a literate number value has its own style" {
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("Loaded {Count} files", [3])
  let record = @formatting.LogRecord::capture(
    memory.events()[0],
    @formatting.LogTimestamp::earliest(),
  )
  let literate = @formatting.format_console(record, Literate)
  assert_true(literate.contains("\u{1b}[95m3\u{1b}[0m"))
  assert_true(literate.has_suffix("\u{1b}[0m\n"))
  assert_false(@formatting.format_console(record, Plain).contains("\u{1b}"))
}
```

## JSON Lines

`format_json_line` gives one JSON object on one physical line, with a final LF.
The output is UTF-8 text with no byte order mark and no ANSI codes. Control
characters in strings, including ESC, CR and LF, are JSON escapes, so a reader
can read one record for each line. The keys of schema version 1 are in this
order:

| Key | Value |
| --- | --- |
| `schemaVersion` | The number `1` |
| `timestamp` | The captured UTC time, for example `"2026-10-27T14:23:07.024Z"` |
| `level` | The level name, for example `"Information"` |
| `category` | The category, or `null` |
| `messageTemplate` | The template as the caller wrote it |
| `message` | The message text |
| `properties` | An array of `{"name": ..., "value": ...}` objects, in hole order |
| `error` | The `Show` text of the error, or `null` |

The properties are an array, not an object keyed by name, so a repeated name
keeps each of its values. Each value keeps its JSON type. A number that is not
finite (NaN or an infinity) becomes `null`, because JSON has no such numbers.
This schema is not the JSON schema of Serilog (Compact JSON or CLEF); do not use
a Serilog reader for it.

```mbt check
///|
test "one JSON Lines record" {
  let memory = @logging.MemoryLogger::new()
  @logging.with_category(memory, "workspace.loader").info(
    "Loaded {Count} files from {Path}",
    [3, "src"],
  )
  let time = @formatting.LogTimestamp::from_epoch_millis(1793110987024L)
  let record = @formatting.LogRecord::capture(memory.events()[0], time)
  inspect(@formatting.format_json_line(record), content=(
    #|{"schemaVersion":1,"timestamp":"2026-10-27T14:23:07.024Z","level":"Information","category":"workspace.loader","messageTemplate":"Loaded {Count} files from {Path}","message":"Loaded 3 files from src","properties":[{"name":"Count","value":3},{"name":"Path","value":"src"}],"error":null}
    #|
  ))
}
```

## Bytes for size limits

A file sink counts bytes, not characters. `utf8_length` gives the UTF-8 bytes of
a rendered record, including its LF:

```mbt check
///|
test "count the bytes of a record" {
  assert_eq(@formatting.utf8_length("ok\n"), 3L)
  assert_eq(@formatting.utf8_length("é✓😀\n"), 10L)
}
```
