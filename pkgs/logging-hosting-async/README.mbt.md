# moonrockz/moon-lander-logging-hosting-async

Console and rolling file delivery for
[Moon-Lander logging](../logging/README.mbt.md). A session owns one logger, one
bounded queue and one writer task. The logger keeps the synchronous `Logger` trait:
a log call captures the record and returns at once, and the writer task writes it
later to a Literate console, readable text files and JSON Lines files.

The module is optional. A library that only writes events depends on
`moonrockz/moon-lander-logging` and on nothing else. This module imports core,
logging and `moonbitlang/async`, and never configuration, mediator or hosting, so
an application can use sinks without the application host.

| Package | What it holds | Targets |
| --- | --- | --- |
| `moonrockz/moon-lander-logging-hosting-async` | Typed settings and report values, the color decision | `wasm`, `wasm-gc`, `js`, `native` |
| `moonrockz/moon-lander-logging-hosting-async/runtime` | Sessions, the writer task, console streams and files ([guide](runtime/README.mbt.md)) | `native`, `js` (Node.js and Bun) |
| `moonrockz/moon-lander-hosting/logging` | The opt-in host bridge that drains before the process ends ([guide](../hosting/logging/README.mbt.md)) | `native`, `js` |

The pure layouts and rolling rules are in
[`logging/formatting`](../logging/formatting/README.mbt.md) and
[`logging/rolling`](../logging/rolling/README.mbt.md). The runtime has no sink on
`wasm`, `wasm-gc` or a browser: an import of the runtime there fails at build time,
and it never drops records silently. Bring your own `Logger` on those targets.

## Settings

Each value with a rule has a smart constructor and a typed `SettingsError`. Parse a
relative directory against an explicit base at your boundary first; `LogDirectory`
takes an already parsed `AbsolutePath`.

```mbt check
///|
test "settings for a console and two file formats" {
  let logs = "/var/log/acme"
    |> @lander_core.AbsolutePath::parse
    |> @sinks.LogDirectory::from_absolute
  let stem = @rolling.LogFileStem::parse("acme")
  let settings = @sinks.SessionSettings::new(
    console=@sinks.ConsoleSink::new(minimum=Debug),
    files=[
      @sinks.FileSink::new(logs, stem),
      @sinks.FileSink::new(logs, stem, format=JsonLines, retention=KeepAll),
    ],
    event_limit=@sinks.QueueEventLimit::count(4096),
  )
  inspect(settings.files()[1].marker_path(), content="/var/log/acme/acme.jsonl.lock")
}
```

| Setting | Default | Rule |
| --- | --- | --- |
| `ConsoleSink` stream | `StandardError` | `StandardOutput` by explicit selection |
| `ConsoleSink` minimum, color, theme | `Information`, `Auto`, `Literate` | Typed cases |
| `FileSink` format, policy, retention | `Text`, `DailyAndSize(10 MiB)`, `KeepNewest(31)` | Typed cases; the count includes the active file |
| `QueueEventLimit` | 1024 records | 1 or more |
| `QueueByteLimit` | 8 MiB | 1 or more |
| `RecordByteLimit` | 1 MiB | 1 or more, and not more than `QueueByteLimit` |
| Drain limit | 5 seconds | A `TimeLimit` |
| File sets | | Two `FileSink` values cannot share a directory, stem and format |

The queue limits count each record that is accepted and not yet written, including
the record that the writer writes now, and the payload bytes of all its
destinations. A single large input can still need temporary memory to encode
before the session rejects it.

## Colors

`ColorMode::Auto` writes styles only when the runtime reports a color terminal, the
stream is not redirected, `TERM` is not `dumb`, and `NO_COLOR` is empty or not set.
`Always` forces the `Literate` theme; `Never` writes plain text.

| Runtime | What Auto knows |
| --- | --- |
| Node.js, Bun | `isTTY` and `hasColors()` of the selected stream |
| native | Nothing: the pinned `moonbitlang/async` has no public terminal check, so Auto stays plain. Use `Always` to force colors |

```mbt check
///|
test "Auto colors are off for an unknown terminal and with NO_COLOR" {
  let console = @sinks.ConsoleSink::new()
  let hints = @sinks.ColorHints::from_env(no_color=Some("1"), term=None)
  let none = @sinks.ColorHints::none()
  assert_true(console.render_theme(ColorTerminal, none) is Literate)
  assert_true(console.render_theme(Unknown, none) is Plain)
  assert_true(console.render_theme(ColorTerminal, hints) is Plain)
}
```

## Reports

`Session::status()` and `Session::close()` give an immutable `SessionReport`: the
accepted records, the drops by reason (`queue_full`, `oversized`, `closed`,
`reentrant`), and for each destination the written and undelivered counts, the
failure that stopped it and the latest retention failure. `delivery_failed()` is
true when a destination failed, a record stayed undelivered or a drain used its
full limit. A drop at admission is visible in the counts, but it is not a delivery
failure.

## Limits

- This is not an audit sink. A full queue drops the newest record, and a log call
  never waits.
- Completion means that the OS or the Node.js stream callback accepted the bytes.
  There is no `fsync`, and a crash or a forced end can lose records.
- One file set has one writer. An ownership marker `<stem>.<extension>.lock` in the
  log directory guards it. A marker that a crash left stays, and the next session
  reports `AcquireOwnership` and writes nothing to that set. Make sure that no
  writer is active, then delete the marker by hand.
- A failed write can leave a partial line at the end of a file. The writer reports
  it, stops that destination and does not write the record again.
- One session runs in one async runtime. Do not share it across threads.
