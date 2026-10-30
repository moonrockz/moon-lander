# Public Moonx launcher

`moonx moonrockz/moon-lander-moonx/launch@VERSION [--json] [--] EXECUTABLE [ARG...]`

Replace `VERSION` with the published shared version. This small executable calls
the public driver. It has no separate process lifetime implementation and no
application payload protocol. Use the library's `NodeLaunch` for embedded files.
Node is a prerequisite when it is the selected executable.

Launcher options stop at `--` or the first executable. Everything after the
executable is an opaque argument, including `--json`, `--help`, empty strings and
Unicode. Use `--` before an executable whose name starts with a dash. `--help` or
`-h` prints help and starts no child. An unknown launcher option, absent
executable, empty executable or unrepresentable process argument selects status 2.

The executable preserves binary stdin/stdout and separate stderr. Once a child
starts, the child owns stdout completely. `--json` does not wrap successful
output, failure output or a child's own JSON. A finite child status is preserved,
including a nonzero status. The public driver owns signal forwarding, deadlines,
reaping and finalization; see [the guide](../GUIDE.md).

## JSON ownership contract

`--json` selects a single parent JSON document only for command help, usage
failure, or a typed outcome proving that no child started. Those reports use
stdout; their human forms use stdout for help and stderr for failures. Parent
startup reporting does not read the child channel. The argument boundary also
prevents an application's `--json` from selecting parent reporting.

Each parent document has `schema_version: 1`,
`command: "moon-lander-moonx/launch"`, `package_version`, `kind` and
`exit_status`. `exit_status` is an unsigned 32-bit number so Windows status bits
are preserved.

| `kind` | Extra fields | Meaning |
| --- | --- | --- |
| `help` | `usage`, `stdout_ownership` | Explicit command help, status 0 |
| `usage-error` | `reason` | Typed argument rule, status 2 |
| `not-started` | `reason`, `finalization_failure_count` | No child started; status selected after cleanup |

Usage reasons are `unknown-option`, `missing-executable`, `invalid-executable`
and `invalid-argument`, with the input, rule or index where relevant. Startup
reasons are `process-start-failed`, `node-missing`, `materialization-failed`,
`signal` and `requested`. A signal reason names its original OS identity.
Error messages are display text; consumers match the documented kinds rather
than parsing messages. Application result schemas remain application-owned.

For example, `--json -- /missing/program` reports `kind: "not-started"`; it
starts no child and selects failure. `--json -- node app.js --json` forwards the
last option to `app.js` and emits no parent document once Node has started.
Cancellation after startup also emits no parent application result.
