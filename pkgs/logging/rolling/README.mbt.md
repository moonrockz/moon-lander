# Rolling log files

The `rolling` package (`@rolling`) decides which file a log record goes to, when
a new file starts and which old files to delete. It is a pure state machine: it
does no I/O and reads no clock. The host file adapter lists the log directory,
opens, writes and deletes files, and gives the results to this package. The
package has the same API on `wasm`, `wasm-gc`, `js` and `native`, and imports
only the MoonBit core library and `@formatting`.

```moonbit notest
///|
import {
  "moonrockz/moon-lander-logging/formatting",
  "moonrockz/moon-lander-logging/rolling",
}
```

## Settings

Each setting with rules is a type with a constructor that checks the rules and
raises a `RollingError` that names the input and the rule.

| Type | Rule | Default |
| --- | --- | --- |
| `LogFileStem` | 1 to 64 characters: an ASCII letter, then ASCII letters, digits, `_` and `-`. Not a Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM0`-`COM9`, `LPT0`-`LPT9`, any letter case). Not `_` or `-` and digits at the end | None |
| `FileByteLimit` | More than 0 bytes | 10 MiB |
| `RetainedFileCount` | More than 0 files | 31 |
| `RollingPolicy` | `Daily`, `Size(limit)` or `DailyAndSize(limit)` | `DailyAndSize(10 MiB)` |
| `Retention` | `KeepNewest(count)` or `KeepAll` | `KeepNewest(31)` |
| `FileFormat` | `Text` (`.log`) or `JsonLines` (`.jsonl`) | `Text` |

The stem cannot end with `_` or `-` and digits because the file names of a
shorter stem have that form. For example, the stem `acme_001` would make
`acme_001.log`, which is the second file of the stem `acme`.

## File names

A `FileSet` is the files of one stem and one format, with one policy. The periods
are UTC days. For the stem `acme`:

| Policy | First file | Next files in the period |
| --- | --- | --- |
| `Daily` or `DailyAndSize` | `acme-20261027.log` | `acme-20261027_001.log`, `acme-20261027_002.log` |
| `Size` | `acme.log` | `acme_001.log`, `acme_002.log` |

`JsonLines` uses `.jsonl` in place of `.log`, so the two formats of one stem can
share a directory. A sequence number has at least three digits, and gets more
digits after 999 (`_1000`). After the largest `Int`, the plan raises
`SequenceExhausted`; it never uses a name again.

`parse_name` accepts only the complete form of an owned name. The ownership
marker, for example `acme.log.lock`, is not an owned name:

```mbt check
///|
test "the file set owns only its exact names" {
  let stem = @rolling.LogFileStem::parse("acme")
  let set = @rolling.FileSet::new(stem, Text, @rolling.RollingPolicy::default())
  assert_true(set.parse_name("acme-20261027_001.log") is Some(_))
  assert_true(set.parse_name("acme-old.log") is None)
  assert_true(set.parse_name("acme-20261027.log.bak") is None)
  assert_true(set.parse_name("acme-20261027.jsonl") is None)
  assert_eq(set.marker_name(), "acme.log.lock")
  assert_true(set.parse_name(set.marker_name()) is None)
}
```

## Plan each record

`RollingState::plan` gives a `FilePlan` for one record of a number of bytes at
the writer time:

| Plan | Adapter action |
| --- | --- |
| `Open(name, existing_size~)` | No file is open. Open `name` to append (never truncate), then write |
| `Append(name)` | Write to the open file |
| `Roll(name)` | Close the active file, open `name` to append, write, then run retention |

After each successful action, the adapter calls `opened(name, size)` and
`wrote(bytes)`. A failed action does not change the state. The rules are:

- The size is the UTF-8 bytes of the rendered record, including its LF and its
  error lines. Use `@formatting.utf8_length`.
- A nonempty file rolls before a record that does not fit. An exact fit appends.
- An empty file takes a record larger than the limit, and the next record rolls.
  A record never splits across files.
- A daily policy rolls at the first record of a later UTC day. When the clock
  moves back, the writer stays in the day of the active file.
- `Size` does not roll at a new day. `Daily` does not roll at any size.
- At the first open, the plan reads the directory listing. It appends to the
  newest owned regular file of the current period when that file has room, and
  else it opens the next sequence number.

```mbt check
///|
test "a day with two size rolls" {
  let stem = @rolling.LogFileStem::parse("acme")
  let limit = @rolling.FileByteLimit::bytes(100L)
  let set = @rolling.FileSet::new(stem, JsonLines, DailyAndSize(limit))
  let now = @formatting.LogTimestamp::from_epoch_millis(1793110987024L)
  let mut state = @rolling.RollingState::new(set)
  let names = []
  for bytes in [60L, 40L, 1L, 99L, 1L] {
    let plan = state.plan(now, bytes, [])
    match plan {
      Append(name) => names.push("append \{name}")
      Open(name, existing_size~) => {
        state = state.opened(name, existing_size)
        names.push("open \{name}")
      }
      Roll(name) => {
        state = state.opened(name, 0L)
        names.push("roll \{name}")
      }
    }
    state = state.wrote(bytes)
  }
  inspect(names.join("\n"), content=(
    #|open acme-20261027.jsonl
    #|append acme-20261027.jsonl
    #|roll acme-20261027_001.jsonl
    #|append acme-20261027_001.jsonl
    #|roll acme-20261027_002.jsonl
  ))
}
```

At a restart, the adapter gives the directory entries. The plan appends to the
existing file and gives its size, so the size limit counts the old bytes:

```mbt check
///|
test "a restart appends to the newest file of the day" {
  let stem = @rolling.LogFileStem::parse("acme")
  let set = @rolling.FileSet::new(stem, Text, @rolling.RollingPolicy::default())
  let now = @formatting.LogTimestamp::from_epoch_millis(1793110987024L)
  let listing : Array[@rolling.ListedFile] = [
    { name: "acme-20261027.log", size: 10485760L, regular: true },
    { name: "acme-20261027_001.log", size: 2048L, regular: true },
    { name: "acme.log.lock", size: 0L, regular: true },
  ]
  let plan = @rolling.RollingState::new(set).plan(now, 120L, listing)
  guard plan is Open(name, existing_size~) else { fail("no open plan") }
  assert_eq(name.to_string(), "acme-20261027_001.log")
  assert_eq(existing_size, 2048L)
}
```

## Retention

After a new file opens, `FileSet::retention` gives the names of the files to
delete. It counts only regular entries whose names have the complete owned form,
so it never deletes directories, links, the marker, another stem, another format
or a similar name such as `acme-20261027.log.bak`. `KeepNewest(n)` keeps the
active file and the newest `n - 1` other owned files. It sorts by UTC day and
then by sequence number, not by modification time. `KeepAll` deletes nothing.

```mbt check
///|
test "keep the newest three files" {
  let stem = @rolling.LogFileStem::parse("acme")
  let set = @rolling.FileSet::new(stem, Text, Daily)
  let names = [
    "acme-20261024.log", "acme-20261025.log", "acme-20261026.log", "acme-20261027.log",
    "acme-20261027.log.bak",
  ]
  let listing = names.map(name => @rolling.ListedFile::{
    name,
    size: 1L,
    regular: true,
  })
  guard set.parse_name("acme-20261027.log") is Some(active) else {
    fail("not owned")
  }
  let retention = @rolling.Retention::KeepNewest(
    @rolling.RetainedFileCount::count(3),
  )
  assert_eq(set.retention(retention, listing, active), ["acme-20261024.log"])
}
```

The adapter deletes the names only after the new file opens. A failed delete is
a retention failure; it does not stop the active file.
