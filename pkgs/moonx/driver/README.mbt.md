# moonrockz/moon-lander-moonx/driver

Call `run` from synchronous `fn main`. It owns the process lifetime and exits
only after reaping, private payload cleanup and callbacks. The package uses the
stock Wasm/native host ABI. Its plan values remain portable to all four targets.
Do not import canonical async into this launcher executable.

Original SIGINT/SIGTERM forwarding is guaranteed on POSIX. Stock Windows Moonrun
delivers Ctrl-C as Ctrl-Break, with genuine Node-host Quit/131 completion and
the parent's real Windows status. The guide states the platform limitation.

```mbt check
///|
/// Body of a synchronous process launcher main.
fn command_example(raw_arguments : Array[String]) -> Unit raise {
  let command = @moonx.Command::new(
    @moonx.Executable::node(),
    @moonx.Arguments::parse(raw_arguments),
  )
  @driver.run(Process(command))
}

///|
/// Body of a synchronous main with an application-owned embedded payload.
fn payload_example() -> Unit raise {
  let entry = @moonx.RelativeFilePath::parse("entry.js")
  let payload = @moonx.Payload::new([
    @moonx.PayloadFile::new(
      @moonx.RelativeFilePath::parse("package.json"),
      b"{\"type\":\"module\"}",
    ),
    @moonx.PayloadFile::new(entry, b"console.log(process.cwd());"),
  ], entry)
  @driver.run(Node(@moonx.NodeLaunch::new(payload, @moonx.Arguments::empty())),
    completed=outcome => {
      match outcome.result() {
        NotStarted(_) => eprintln("Application may report its startup result here")
        Started(_) => ()
      }
    },
  )
}

///|
test "public synchronous launcher examples compile" {
  // run owns process exit; acceptance executes these APIs in child processes.
  ignore(command_example)
  ignore(payload_example)
}
```

See [the guide](../GUIDE.md) for signals, opaque transport, payload path rules,
callback ordering and Windows status semantics. The application owns its result
schema. The driver adds no application document to stdout.
