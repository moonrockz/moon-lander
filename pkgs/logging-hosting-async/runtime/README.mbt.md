# moonrockz/moon-lander-logging-hosting-async/runtime

Logging sessions on `native` and on `js` under Node.js and Bun. `with_session`
starts the writer task, runs your code with the session, then closes the session:
it drains the accepted records, closes the files and deletes their ownership
markers. Use it without a host, or through the host bridge
[`moonrockz/moon-lander-hosting/logging`](../../hosting/logging/README.mbt.md).

```mbt check
///|
/// A standalone program that logs to standard error and a rolling text file.
async fn standalone_main() -> Unit {
  let logs = "/var/log/acme"
    |> @lander_core.AbsolutePath::parse
    |> @sinks.LogDirectory::from_absolute
  let settings = @sinks.SessionSettings::new(
    console=@sinks.ConsoleSink::new(),
    files=[@sinks.FileSink::new(logs, @rolling.LogFileStem::parse("acme"))],
  )
  let report = @runtime.with_session(settings, session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("Loaded {Count} files from {Path}", [Json::number(3.0), Json::string("src")])
    session.close()
  })
  for message in report.failure_messages() {
    ignore(@runtime.write_diagnostic(message))
  }
}

///|
test "the standalone example compiles" {
  ignore(standalone_main)
}
```

## The pipeline

1. A log call checks the levels: a session that is open takes a level when a
   destination that has not failed takes it. A full queue does not turn a level
   off, so its drops are counted.
2. The logger captures one record: the UTC time from the clock, a sequence number,
   the event and the `Show` text of its error. It renders the payload of each
   destination at once, so all destinations show the same record.
3. Admission accepts the record, or counts it as `oversized` or `queue_full`. A
   log call from the failure observer, or from the `Show` of an error while the
   logger runs, is counted as `reentrant`.
4. The one writer task writes the records in order. A file destination opens its
   directory, its marker and its file at the first record for it, and selects the
   file from the rolling plan with the writer clock.
5. A failed write stops that destination. Its later records are undelivered;
   other destinations continue. The optional `observer` gets each failure.
6. `drain()` waits for the records that were accepted before the call. Producers
   that continue do not make it longer. `close()` stops admission, drains within the
   drain limit and gives the final report. A second `close()` gives the same report.

Use `clock=` to give a fixed or stepped time in tests. The writer reads the same
clock to select the rolling period, and it never moves back to an older period.

## Node.js and Bun

The pinned `moonbitlang/async` has no `fs` or `stdio` on js. A small TypeScript
adapter in `pkgs/logging-hosting-async/adapters/node/` uses only `node:*` modules:

| Operation | Node.js API |
| --- | --- |
| Console write | `process.stdout` or `process.stderr` `write`, complete at the callback |
| Terminal check | `isTTY` and `hasColors()` |
| Directory | `fs/promises.mkdir` with `recursive` |
| Ownership marker | `fs/promises.open(path, "wx")` (exclusive create) |
| Log file | `open(path, "a")`, `stat`, `write` until all bytes are written, `close` |
| Retention | `readdir` and `lstat` (links are not followed), `unlink` |

The adapter adds an `error` listener to a console stream the first time that it
writes to that stream, so a closed pipe gives a reported write failure and does not
end the process. `scripts/build-node-adapter.mbtx` bundles the adapter into
`node.generated.js.mbt`; do not edit that file.
