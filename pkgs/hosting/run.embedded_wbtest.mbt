///|
// Test-only suspension point: the closure stops here, and the test keeps the
// continuation. Production code never suspends without an event loop.
async fn[T] suspend_here(register : ((T) -> Unit) -> Unit) -> T noraise + nocancel = "%async.suspend"

///|
suberror EmbeddedTestError { Broken(String) } derive(Debug)

///|
pub extend EmbeddedTestError with @debug.Debug::{to_repr}

///|
/// Run with a captured report writer. It gives the outcome and the lines.
fn[S] embedded(host : Host[S], command : Hook[S], stop_probe? : () -> Bool) -> (RunOutcome, Array[String]) {
  let lines = []
  let result = run_embedded_with_writer(host, command, stop_probe?, write_line=line => lines.push(line),
    write_output=text => abort("unexpected standard output: \{text}"))
  (result, lines)
}

///|
/// Run with captured writers. It gives the outcome, the standard output texts
/// and the report lines.
fn[S] embedded_output(host : Host[S]) -> (RunOutcome, Array[String], Array[String]) {
  let output = []
  let lines = []
  let result = run_embedded_with_writer(host, _ => abort("unexpected command"),
    write_line=line => lines.push(line), write_output=text => output.push(text))
  (result, output, lines)
}

///|
/// A command with a version, and a subcommand with a required argument.
fn help_command(name : String) -> @hosting_argparse.Command {
  @hosting_argparse.Command(name, version="1.2.3", options=[@hosting_argparse.config_option()],
    subcommands=[@hosting_argparse.Command("build", about="Build the project.",
      positionals=[@hosting_argparse.PositionArg("target", num_args=@hosting_argparse.ValueRange::single())])])
}

///|
/// A host with `help_command`. Its file tree is empty, so a configuration load
/// gives code 2, and the factory and the hook record each call.
fn help_host(argv : Array[String], calls : Array[String]) -> Host[Unit] raise {
  builder(@lander_core.AppName::parse("acme"), argv)
  |> @hosting_argparse.command(help_command)
  |> configure(s => s |> @config.format(@toml.format()))
  |> app_dirs() |> files(@config.FileTree::new())
  |> service("a", starting=_ => calls.push("hook"))
  |> build(_ => calls.push("factory"))
}

///|
test "help returns its text once with code 0 and reads no file before the factory" {
  // `render_help` ends with a newline; the request text does not.
  let help = help_command("acme").render_help()
  for argv in [["--help"], ["-h"], ["--config", "missing.toml", "--help"]] {
    let calls = []
    let (result, output, lines) = embedded_output(help_host(argv, calls))
    assert_eq(result.exit_code.to_int(), 0, msg=argv.join(" "))
    assert_eq(result.failures.length(), 0)
    assert_true(result.reason is Requested)
    assert_eq(output.length(), 1)
    assert_eq(output[0] + "\n", help)
    assert_eq(calls, [])
    assert_eq(lines, [])
  }
}

///|
test "subcommand help and help with a missing required argument return the subcommand text" {
  for argv in [["help", "build"], ["build", "--help"]] {
    let calls = []
    let (result, output, _) = embedded_output(help_host(argv, calls))
    assert_eq(result.exit_code.to_int(), 0, msg=argv.join(" "))
    assert_true(result.reason is Requested)
    assert_eq(output.length(), 1)
    assert_true(output[0].contains("Build the project."), msg=output[0])
    assert_true(output[0].contains("<target>"), msg=output[0])
    assert_eq(calls, [])
  }
}

///|
test "version returns its text once with code 0 to the caller" {
  let calls = []
  let (result, output, lines) = embedded_output(help_host(["--version"], calls))
  assert_eq(result.exit_code.to_int(), 0)
  assert_true(result.reason is Requested)
  assert_eq(result.failures.length(), 0)
  assert_eq(output, ["1.2.3"])
  assert_eq(calls, [])
  assert_eq(lines, [])
}

///|
test "a usage error still gives 2 and writes no standard output" {
  let calls = []
  let (result, output, lines) = embedded_output(help_host(["--no-such-option"], calls))
  assert_eq(result.exit_code.to_int(), 2)
  assert_eq(output, [])
  assert_eq(lines.length(), 1)
  assert_eq(calls, [])
}

///|
/// Services `a`, `b` and `c` log each start and stop hook into `log`.
fn embedded_services(log : Array[String], fail_start? : String, fail_stop? : String) -> Host[Unit] raise {
  let mut host : HostBuilder[Unit] = builder(@lander_core.AppName::parse("acme"), [])
  for name in ["a", "b", "c"] {
    host = host |> service(name,
      start=_ => {
        log.push("\{name}.start")
        if fail_start == Some(name) { raise Broken(name) }
      },
      stop=_ => {
        log.push("\{name}.stop")
        if fail_stop == Some(name) { raise Broken(name) }
      },
    )
  }
  host |> build(_ => ())
}

///|
test "a clean embedded run starts in order, stops in reverse and gives 0" {
  let log = []
  let (result, lines) = embedded(embedded_services(log), _ => log.push("command"))
  assert_eq(result.exit_code.to_int(), 0)
  assert_eq(result.failures.length(), 0)
  assert_true(result.reason is Completed)
  assert_eq(log, ["a.start", "b.start", "c.start", "command", "c.stop", "b.stop", "a.stop"])
  assert_eq(lines, [])
}

///|
test "the public embedded driver runs a clean host" {
  let log = []
  let result = run_embedded(embedded_services(log), _ => log.push("command"))
  assert_eq(result.exit_code().to_int(), 0)
  assert_eq(log.length(), 7)
}

///|
test "a failing command gives 1, runs the stop hooks and reports on standard error" {
  let log = []
  let (result, lines) = embedded(embedded_services(log), _ => raise Broken("command"))
  assert_eq(result.exit_code.to_int(), 1)
  assert_true(result.failures is [Broken("command")])
  assert_true(result.reason is Failed(Broken("command")))
  assert_eq(log, ["a.start", "b.start", "c.start", "c.stop", "b.stop", "a.stop"])
  assert_eq(lines, ["acme: moonrockz/moon-lander-hosting.EmbeddedTestError.Broken"])
}

///|
test "a start failure skips the command and stops only the started services" {
  let log = []
  let (result, lines) = embedded(embedded_services(log, fail_start="b"), _ => log.push("command"))
  assert_eq(result.exit_code.to_int(), 1)
  assert_true(result.reason is StartFailed(Broken("b")))
  assert_eq(log, ["a.start", "b.start", "a.stop"])
  assert_eq(lines.length(), 1)
}

///|
test "a stop failure does not skip the other stop hooks" {
  let log = []
  let (result, _) = embedded(embedded_services(log, fail_stop="b"), _ => log.push("command"))
  assert_eq(result.exit_code.to_int(), 1)
  assert_true(result.failures is [Broken("b")])
  assert_true(result.reason is Completed)
  assert_eq(log, ["a.start", "b.start", "c.start", "command", "c.stop", "b.stop", "a.stop"])
}

///|
test "hooks and events follow the shared engine order" {
  let log = []
  let mut host : HostBuilder[Unit] = builder(@lander_core.AppName::parse("acme"), [])
  for i in 0..<2 {
    let hook = (name : String) => {
      let logged : Hook[Unit] = _ => log.push("\{i}.\{name}")
      logged
    }
    host = host |> service("service-\{i}", starting=hook("Starting"), start=hook("Start"), started=hook("Started"),
      stopping=hook("Stopping"), stop=hook("Stop"), stopped=hook("Stopped"))
  }
  host = host |> service("events", starting=ctx => {
    ctx.lifetime.on_started(() => log.push("event.Started"))
    ctx.lifetime.on_stopping(() => log.push("event.Stopping"))
    ctx.lifetime.on_stopped(() => log.push("event.Stopped"))
  })
  let (result, _) = embedded(host |> build(_ => ()), _ => log.push("command"))
  assert_eq(result.exit_code.to_int(), 0)
  // The third service has only a starting hook.
  let (expected, _) = engine_trace([63, 63, 1])
  assert_eq(log.filter(entry => entry != "2.Starting"), expected.filter(entry => entry != "2.Starting"))
}

///|
test "a suspending start hook fails with code 1 and a message" {
  let log = []
  let held : Array[() -> Unit] = []
  let host = builder(@lander_core.AppName::parse("acme"), [])
    |> service("a", start=_ => log.push("a.start"), stop=_ => log.push("a.stop"))
    |> service("db", start=_ => {
      log.push("db.start")
      suspend_here(wake => held.push(() => wake(())))
      log.push("db.resumed")
      raise Broken("late")
    }, stop=_ => log.push("db.stop"))
    |> build(_ => ())
  let (result, lines) = embedded(host, _ => log.push("command"))
  assert_eq(result.exit_code.to_int(), 1)
  guard result.failures is [HookSuspended(service~, phase~) as error] else { fail("expected HookSuspended") }
  assert_eq(service.to_string(), "db")
  assert_eq(phase, HookPhase::Start)
  assert_true(result.reason is StartFailed(HookSuspended(..)))
  assert_eq(log, ["a.start", "db.start", "a.stop"])
  let message = "The start hook of service \"db\" suspended. On wasm and wasm-gc, hooks and the command must not wait: remove the wait, or run the host on native or js"
  assert_eq((error : SuspendError).message(), message)
  assert_eq(lines, ["acme: " + message])
  // A late resume runs the rest of the hook, but the completed run stays the same.
  assert_eq(held.length(), 1)
  held[0]()
  assert_eq(log, ["a.start", "db.start", "a.stop", "db.resumed"])
  assert_eq(result.exit_code.to_int(), 1)
  assert_eq(result.failures.length(), 1)
}

///|
test "a suspending command fails with code 1 and the stop hooks run" {
  let log = []
  let held : Array[() -> Unit] = []
  let command : Hook[Unit] = ctx => {
    log.push("command")
    suspend_here(wake => held.push(() => wake(())))
    ctx.lifetime.set_exit_code(ExitCode::from_int(7))
    raise Broken("late")
  }
  let (result, lines) = embedded(embedded_services(log), command)
  assert_eq(result.exit_code.to_int(), 1)
  assert_true(result.failures is [CommandSuspended])
  assert_true(result.reason is Failed(CommandSuspended))
  assert_eq(log, ["a.start", "b.start", "c.start", "command", "c.stop", "b.stop", "a.stop"])
  assert_eq(lines, ["acme: The command suspended. On wasm and wasm-gc, hooks and the command must not wait: remove the wait, or run the host on native or js"])
  held[0]()
  assert_eq(result.exit_code.to_int(), 1)
  assert_eq(result.failures.length(), 1)
}

///|
test "a closed step keeps its suspended result after a late resume" {
  let held : Array[() -> Unit] = []
  let resumed = Ref(false)
  let completion = run_to_completion(() => {
    suspend_here(wake => held.push(() => wake(())))
    resumed.val = true
    raise Broken("late")
  })
  assert_true(completion is Suspended)
  held[0]()
  assert_true(resumed.val)
  assert_true(run_to_completion(() => ()) is Returned)
  assert_true(run_to_completion(() => raise StopRequested::StopRequested) is Stopped)
  assert_true(run_to_completion(() => raise Broken("x")) is Failed(Broken("x")))
}

///|
test "the embedder probe stops a polling command with reason Embedder" {
  let log = []
  let probe_reads = Ref(0)
  let polls = Ref(0)
  let host = builder(@lander_core.AppName::parse("acme"), [])
    |> service("a", start=ctx => {
      log.push("a.start")
      ctx.lifetime.on_stopping(() => log.push(if ctx.lifetime.stop_reason() is Some(Embedder) { "stopping: Embedder" } else { "stopping: other" }))
    }, stop=_ => log.push("a.stop"))
    |> build(_ => ())
  let (result, lines) = embedded(host, ctx => {
    while !ctx.cancelled() { polls.val += 1 }
    log.push("command returned")
  }, stop_probe=() => {
    probe_reads.val += 1
    // The driver reads the probe after the start hook; the command polls next.
    probe_reads.val > 4
  })
  assert_eq(result.exit_code.to_int(), 0)
  assert_true(result.reason is Embedder)
  assert_eq(result.failures.length(), 0)
  assert_true(polls.val > 0)
  assert_eq(log, ["a.start", "command returned", "stopping: Embedder", "a.stop"])
  assert_eq(lines, [])
}

///|
test "the embedder probe during start skips the command" {
  let log = []
  let (result, _) = embedded(embedded_services(log), _ => log.push("command"), stop_probe=() => log.length() >= 2)
  assert_true(result.reason is Embedder)
  assert_eq(result.exit_code.to_int(), 0)
  assert_eq(log, ["a.start", "b.start", "b.stop", "a.stop"])
}

///|
test "an embedder stop before the first hook runs no hook" {
  let log = []
  let (result, _) = embedded(embedded_services(log), _ => log.push("command"), stop_probe=() => true)
  assert_true(result.reason is Embedder)
  assert_eq(result.exit_code.to_int(), 0)
  assert_eq(log, [])
}

///|
test "an embedder stop before the first hook runs no stop hook of a service without start hooks" {
  // A service without `starting` and `start` hooks is started when the start
  // phase reaches it. A stop before the first step reaches no service.
  let log = []
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), [])
    |> service("a", stopping=_ => log.push("a.stopping"), stop=_ => log.push("a.stop"))
    |> service("b", start=_ => log.push("b.start"), stop=_ => log.push("b.stop"))
    |> build(_ => ())
  let (result, _) = embedded(host, _ => log.push("command"), stop_probe=() => true)
  assert_true(result.reason is Embedder)
  assert_eq(log, [])
}

///|
test "stop_application from the command runs the stop phase and gives 0" {
  let log = []
  let (result, _) = embedded(embedded_services(log), ctx => {
    ctx.lifetime.stop_application()
    log.push("cancelled: \{ctx.cancelled()}")
  })
  assert_eq(result.exit_code.to_int(), 0)
  assert_true(result.reason is Requested)
  assert_eq(log, ["a.start", "b.start", "c.start", "cancelled: true", "c.stop", "b.stop", "a.stop"])
}

///|
test "a raised StopRequested is a stop and adds no failure" {
  let log = []
  let (result, lines) = embedded(embedded_services(log), ctx => {
    ctx.lifetime.stop_application(exit_code=ExitCode::from_int(4))
    ctx.check_cancelled()
    log.push("not reached")
  })
  assert_eq(result.exit_code.to_int(), 4)
  assert_eq(result.failures.length(), 0)
  assert_true(result.reason is Requested)
  assert_eq(log, ["a.start", "b.start", "c.start", "c.stop", "b.stop", "a.stop"])
  assert_eq(lines, [])
}

///|
test "omitted embedded settings are empty variables and the root" {
  let seen = []
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), [])
    |> build(b => seen.push("factory: \{b.env_vars.length()} \{b.working_dir}"))
  let (result, _) = embedded(host, ctx => seen.push("command: \{ctx.env_vars.length()} \{ctx.working_dir} \{ctx.environment.content_root}"))
  assert_eq(result.exit_code.to_int(), 0)
  assert_eq(seen, ["factory: 0 /", "command: 0 / /"])
}

///|
test "explicit embedded settings reach the factory, hooks and command" {
  let seen = []
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=({ "HOME": "/home/test" } : Map[String, String]),
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> service("a", start=ctx => seen.push("hook: \{ctx.env_vars.get("HOME").unwrap_or("")} \{ctx.working_dir}"))
    |> build(b => seen.push("factory: \{b.env_vars.get("HOME").unwrap_or("")} \{b.working_dir}"))
  let (result, _) = embedded(host, ctx => seen.push("command: \{ctx.env_vars.get("HOME").unwrap_or("")} \{ctx.working_dir}"))
  assert_eq(result.exit_code.to_int(), 0)
  assert_eq(seen, [
    "factory: /home/test /w", "hook: /home/test /w", "command: /home/test /w",
  ])
}

///|
test "a complete injected tree gives the configuration" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/", [{ name: "acme.toml", kind: File }])
    .with_file("/acme.toml", "log.format = \"text\"")
  let host = builder(@lander_core.AppName::parse("acme"), [])
    |> configure(s => s |> @config.format(@toml.format()))
    |> app_dirs() |> files(tree) |> build(_ => ())
  let formats = []
  let (result, _) = embedded(host, ctx => formats.push(@config.get_text(ctx.config, "log.format")))
  assert_eq(result.exit_code.to_int(), 0)
  assert_eq(formats, ["text"])
}

///|
test "an incomplete injected tree gives 2 and names the paths before the factory" {
  let calls = []
  let host = builder(@lander_core.AppName::parse("acme"), [])
    |> configure(s => s |> @config.format(@toml.format()))
    |> app_dirs() |> files(@config.FileTree::new())
    |> service("a", starting=_ => calls.push("hook"))
    |> build(_ => calls.push("factory"))
  let (result, lines) = embedded(host, _ => calls.push("command"))
  assert_eq(result.exit_code.to_int(), 2)
  assert_true(result.failures is [IncompleteFileTree(..)])
  assert_eq(calls, [])
  assert_eq(lines.length(), 1)
  guard result.failures is [IncompleteFileTree(requests~)] else { fail("expected one incomplete tree") }
  let paths = requests.map(request => match request { ListDir(path) | ReadFile(path) => path })
  assert_true(paths.length() > 0)
  // The report names every requested path, in request order.
  assert_eq(lines[0], "acme: Incomplete configuration file tree; requested paths: " + paths.join(", "))
}

///|
test "a custom report runs without an event loop and a suspending report is ignored" {
  let reports = []
  let held : Array[() -> Unit] = []
  let host = builder(@lander_core.AppName::parse("acme"), [])
    |> service("a", stop=_ => raise Broken("stop"))
    |> error_report((error, code) => {
      if error is Broken("command") {
        suspend_here(wake => held.push(() => wake(())))
      }
      let name = if error is Broken(name) { name } else { "other" }
      reports.push("\{name} \{code.to_int()}")
    })
    |> build(_ => ())
  let (result, lines) = embedded(host, _ => raise Broken("command"))
  assert_eq(result.exit_code.to_int(), 1)
  assert_eq(result.failures.length(), 2)
  assert_eq(reports, ["stop 1"])
  assert_eq(lines, [])
  held[0]()
  assert_eq(reports, ["stop 1", "command 1"])
  assert_eq(result.failures.length(), 2)
}

///|
test "a factory StopRequested ends the run with code 0 before any hook" {
  let log = []
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), [])
    |> service("a", starting=_ => log.push("hook"))
    |> build(_ => raise StopRequested::StopRequested)
  let (result, _) = embedded(host, _ => log.push("command"))
  assert_eq(result.exit_code.to_int(), 0)
  assert_true(result.reason is Requested)
  assert_eq(log, [])
}
