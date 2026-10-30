# Moonx process launcher

`moonrockz/moon-lander-moonx` is an optional parent process adapter. Its root
package contains portable immutable launch values. The process driver owns a
separate runtime; keep canonical hosting and actors in the application process.

Parse executable text and arguments once. Empty arguments, delimiters, Unicode
and newlines remain opaque. NUL is rejected because OS argument arrays cannot
represent it. A shutdown grace period is positive and defaults to five seconds.

The Node executable must be available on PATH, or the application supplies an
explicit executable. This module does not install Node or own application schemas.

Original SIGINT/SIGTERM forwarding is guaranteed on POSIX. Stock Windows Moonrun
delivers parent Ctrl-C as Ctrl-Break to Node, whose genuine host reports Quit/131.
The parent retains its original observation and full Windows status. See the
guide for this limitation and actual Windows cleanup qualification.

The [launcher and payload guide](GUIDE.md) describes the public synchronous
driver, private Node payloads and typed completion callbacks. [Runtime
provenance](RUNTIME.md) records the frozen source, test inputs and removal path.

```mbt check
///|
test "construct an immutable Node payload plan" {
  let entry = @moonx.RelativeFilePath::parse("app/entry.js")
  let payload = @moonx.Payload::new([
    @moonx.PayloadFile::new(entry, b"process.exitCode = 23;"),
  ], entry)
  let arguments = @moonx.Arguments::parse(["", "--", "a b", "é🙂"])
  let plan = @moonx.NodeLaunch::new(payload, arguments)
  assert_eq(plan.payload().entry().to_string(), "app/entry.js")
  assert_eq(plan.arguments().to_array(), ["", "--", "a b", "é🙂"])
}
```
