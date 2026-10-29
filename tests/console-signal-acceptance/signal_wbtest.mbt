///|
/// The tests start child processes that run the test host of
/// `console-host-scenarios` with the console driver. A native child is this
/// test binary again, with only the helper test (the first test in this file).
/// A js child is the program `console-host-program` under Node.js or Bun.
/// This variable selects the scenario of the child. Without it, the helper
/// test passes at once.
let scenario_var : String = "LANDER_CONSOLE_SCENARIO"

///|
/// The path of the built js program. `mise run check:console` sets it. Without
/// it, the js tests pass at once.
let js_program_var : String = "LANDER_CONSOLE_JS_PROGRAM"

///|
/// The js runtimes to test, separated by commas, for example `node,bun`.
let js_runtimes_var : String = "LANDER_CONSOLE_JS_RUNTIMES"

///|
/// Send the stop signal `kind` (1 Interrupt, 2 Terminate, 3 Quit) to the
/// process `pid` through `send.c`. Gives 0 on success.
extern "C" fn send_signal(pid : Int, kind : Int) -> Int = "lander_test_send_signal"

///|
/// Index 0 of this file: the body of a native child process.
async test "helper: the child process body" {
  guard @env.get_env_var(scenario_var) is Some(text) else { return }
  guard @scenarios.Scenario::parse(text) is Some(scenario) else {
    fail("unknown scenario: " + text)
  }
  @scenarios.run(scenario)
}

///|
/// A child process that runs the test host.
priv enum Child {
  Native
  Js(runtime~ : String, program~ : String)
  Worker(launcher~ : String, program~ : String)
}

///|
fn Child::label(self : Child) -> String {
  match self {
    Native => "native"
    Js(runtime~, ..) => runtime
    Worker(..) => "node worker"
  }
}

///|
/// One step of the parent: wait for a line of the child, or send a signal.
priv enum Step {
  Await(String)
  Send(Int)
  /// Send the signal again every 100 ms until the child ends. Two pending
  /// POSIX signals of one kind merge into one, and a child that never yields
  /// cannot write a line after the first signal, so one more send is not
  /// enough proof that the child got two signals.
  SendUntilExit(Int)
}

///|
/// The phase retained if a bounded child wait times out.
priv enum ChildPhase {
  Starting
  Awaiting(String)
  Signalling(Int)
  ReadingOutput
  WaitingForExit
} derive(Debug)

///|
/// Start `child` in `scenario`, do the steps in order, read the rest of the
/// output, and give the exit code and the full output. Every wait is bounded,
/// and the task group ends the child when a step fails.
async fn run_child(child : Child, scenario : String, steps : Array[Step]) -> (Int, String) {
  let (command, args) = match child {
    Native => {
      let args = @env.args()
      guard args.length() > 1 && args[1].split(":").next() is Some(file) else {
        fail("unexpected test arguments: " + args.join(" "))
      }
      (args[0], ["\{file}:0-1"])
    }
    // `moonbitlang/async` builds the environment of a child without the
    // Windows per-drive entries (`=D:`). Node.js then cannot find the real path
    // of a main script on that drive (`lstat 'D:'`), so it keeps the path as
    // given. The flag has no other effect on this one-file program.
    Js(runtime="node", program~) => ("node", ["--preserve-symlinks-main", program])
    Js(runtime~, program~) => (runtime, [program])
    Worker(launcher~, program~) =>
      ("node", ["--preserve-symlinks-main", launcher, program])
  }
  let output = StringBuilder()
  let phase = Ref(ChildPhase::Starting)
  try @async.with_timeout(20000, () => {
    @async.with_task_group(group => {
      let (reader, writer) = @process.read_from_process()
      let process = @process.spawn(
        group,
        command,
        args,
        extra_env=Map::from_array([(scenario_var, scenario)]),
        stdout=writer,
      )
      writer.close()
      let received : @async.Queue[String?] = @async.Queue(kind=Unbounded)
      let stdout = group.spawn(() => {
        while reader.read_until("\n") is Some(line) {
          let line = line.trim_end(chars="\r").to_owned()
          output.write_string(line + "\n")
          received.put(Some(line))
        }
        received.put(None)
      })
      let mut exit_code : Int? = None
      for step in steps {
        match step {
          Await(line) => {
            phase.val = Awaiting(line)
            for ;; {
              match received.get() {
                Some(actual) if actual.has_suffix(line) => break
                Some(_) => ()
                None => fail("\{child.label()} \{scenario}: no line \{line} in\n\{output}")
              }
            }
          }
          Send(kind) => {
            phase.val = Signalling(kind)
            let sent = send_signal(process.pid, kind)
            guard sent == 0 else { fail("sending kind \{kind} failed: \{sent}") }
          }
          SendUntilExit(kind) =>
            while exit_code is None {
              phase.val = Signalling(kind)
              // A send can fail after the child ends and before the wait sees it.
              ignore(send_signal(process.pid, kind))
              @async.sleep(100)
              exit_code = process.try_wait()
            }
        }
      }
      phase.val = ReadingOutput
      stdout.wait()
      phase.val = WaitingForExit
      let code = match exit_code {
        Some(code) => code
        None => process.wait()
      }
      (code, output.to_string().replace_all(old="\r\n", new="\n"))
    })
  }) catch {
    @async.TimeoutError => fail("\{child.label()} \{scenario} timed out in \{@debug.to_string(phase.val)}; captured stdout:\n\{output}")
    other => raise other
  }
}

///|
/// Check that `lines` occur in `output` as whole lines, in this order.
fn assert_in_order(output : String, lines : Array[String]) -> Unit raise {
  let actual = output.split("\n").map(line => line.to_owned()).collect()
  let mut at = 0
  for line in lines {
    while at < actual.length() && actual[at] != line {
      at += 1
    }
    guard at < actual.length() else {
      fail("missing or out of order: \{line}\n\{output}")
    }
    at += 1
  }
}

///|
/// Check that no line of `output` is `line`.
fn assert_absent(output : String, line : String) -> Unit raise {
  for actual in output.split("\n") {
    guard actual != line else { fail("unexpected line: \{line}\n\{output}") }
  }
}

///|
let start_hooks : Array[String] = [
  "hook=a.starting", "hook=b.starting", "hook=a.start", "hook=b.start", "hook=a.started",
  "hook=b.started",
]

///|
let stop_hooks : Array[String] = [
  "hook=b.stopping", "hook=a.stopping", "hook=b.stop", "hook=a.stop", "hook=b.stopped",
  "hook=a.stopped",
]

///|
/// The kinds that this platform can send to one child process, with the
/// reason text and the exit code. Windows sends only `CTRL_BREAK_EVENT` to one
/// process group (spike lander-4us.5.1).
fn sendable_kinds() -> Array[(Int, String, Int)] {
  match @async.platform {
    Windows => [(3, "Quit", 131)]
    _ => [(1, "Interrupt", 130), (2, "Terminate", 143), (3, "Quit", 131)]
  }
}

///|
/// The native child and, when `mise run check:console` gives the program, a js
/// child for each runtime.
fn children(native~ : Bool) -> Array[Child] {
  let children = if native { [Native] } else { [] }
  guard @env.get_env_var(js_program_var) is Some(program) else { return children }
  let runtimes = @env.get_env_var(js_runtimes_var).unwrap_or("node")
  for runtime in runtimes.split(",") {
    children.push(Js(runtime=runtime.to_owned(), program~))
  }
  children
}

///|
async test "a clean run runs all hooks and ends with 0" {
  for child in children(native=true) {
    let (code, output) = run_child(child, "clean", [])
    assert_in_order(output, start_hooks + ["command"] + stop_hooks)
    assert_in_order(output, ["hook=a.stopping", "reason=Completed"])
    assert_eq(code, 0, msg="\{child.label()}\n\{output}")
  }
}

///|
async test "parent signals stop a non-yielding worker and drain once with true signal codes" {
  guard !(@async.platform is Windows) else { return }
  guard @env.get_env_var("LANDER_CONSOLE_WORKER_LAUNCHER") is Some(launcher) else { return }
  guard @env.get_env_var("LANDER_CONSOLE_WORKER_PROGRAM") is Some(program) else { fail("missing worker program") }
  for (kind, name, expected) in [(1, "Interrupt", 130), (2, "Terminate", 143)] {
    let (code, output) = run_child(Worker(launcher~, program~), "poll", [Await("ready"), Send(kind)])
    assert_eq(code, expected, msg=output)
    assert_in_order(output, start_hooks + ["ready"] + stop_hooks + [
      "finalizer=begin", "drained=true", "finalizer=end", "owner-listeners=intact",
    ])
    assert_in_order(output, ["reason=Signal(\{name})", "polled=true"])
    for line in stop_hooks + ["finalizer=begin", "drained=true", "finalizer=end"] {
      assert_eq(output.split(line + "\n").count() - 1, 1, msg=output)
    }
  }
}

///|
async test "help and version end the process with 0 before any hook" {
  for child in children(native=true) {
    for (scenario, text) in [("help", "Usage: console-host"), ("version", "1.2.3")] {
      let (code, output) = run_child(child, scenario, [])
      assert_eq(code, 0, msg="\{child.label()} \{scenario}\n\{output}")
      assert_eq(output.split(text).count() - 1, 1, msg="\{child.label()} \{scenario}\n\{output}")
      assert_false(output.contains("hook="), msg=output)
      assert_false(output.contains("command"), msg=output)
    }
  }
}

///|
async test "a first signal stops gracefully with its identity, all stop hooks and its code" {
  for child in children(native=true) {
    for case in sendable_kinds() {
      let (kind, name, exit_code) = case
      let (code, output) = run_child(child, "wait", [Await("ready"), Send(kind)])
      assert_in_order(output, start_hooks + ["ready"] + stop_hooks)
      assert_in_order(output, ["hook=a.stopping", "reason=Signal(\{name})"])
      assert_absent(output, "command must be cancelled")
      // A normal exit with the mapped code: no default signal action and no
      // core dump for SIGQUIT.
      assert_eq(code, exit_code, msg="\{child.label()} \{name}\n\{output}")
    }
  }
}

///|
async test "a second signal during a slow stop hook ends the process at once" {
  for child in children(native=true) {
    for case in sendable_kinds() {
      let (kind, name, exit_code) = case
      let (code, output) = run_child(child, "slow-stop", [
        Await("ready"),
        Send(kind),
        Await("slow"),
        Send(kind),
      ])
      assert_in_order(output, [
        "hook=b.stopping", "hook=a.stopping", "reason=Signal(\{name})", "hook=b.stop",
        "slow",
      ])
      for line in ["b.stop.end", "hook=a.stop", "hook=b.stopped", "hook=a.stopped"] {
        assert_absent(output, line)
      }
      assert_eq(code, exit_code, msg="\{child.label()} \{name}\n\{output}")
    }
  }
}

///|
async test "the exit code of a different second signal wins" {
  guard !(@async.platform is Windows) else { return }
  for child in children(native=true) {
    let (code, output) = run_child(child, "slow-stop", [
      Await("ready"),
      Send(1),
      Await("slow"),
      Send(2),
    ])
    assert_in_order(output, ["reason=Signal(Interrupt)", "slow"])
    assert_absent(output, "hook=a.stop")
    assert_eq(code, 143, msg="\{child.label()}\n\{output}")
  }
}

///|
/// A js listener cannot run during a loop that never yields (design, Platform
/// limits 3), so these two tests use only the native child.
async test "a synchronous native loop that polls sees the first signal" {
  for case in sendable_kinds() {
    let (kind, name, exit_code) = case
    let (code, output) = run_child(Native, "poll", [Await("ready"), Send(kind)])
    assert_in_order(output, [
      "ready", "hook=b.stopping", "hook=a.stopping", "reason=Signal(\{name})", "polled=true",
      "hook=a.stopped",
    ])
    assert_eq(code, exit_code, msg="\{name}\n\{output}")
  }
}

///|
async test "a native loop with no check ends at the second signal" {
  for case in sendable_kinds() {
    let (kind, name, exit_code) = case
    let (code, output) = run_child(Native, "spin", [
      Await("ready"),
      Send(kind),
      SendUntilExit(kind),
    ])
    // The command never yields, so the stop phase never starts.
    assert_absent(output, "hook=b.stopping")
    assert_eq(code, exit_code, msg="\{name}\n\{output}")
  }
}

///|
async test "piped output is complete after a clean run and after a graceful signal stop" {
  let lines = Array::makei(@scenarios.output_lines, @scenarios.output_line)
  for child in children(native=true) {
    let (code, output) = run_child(child, "output", [])
    assert_in_order(output, lines + ["end"] + stop_hooks)
    assert_eq(code, 0, msg=child.label())
    let (kind, _, exit_code) = sendable_kinds()[0]
    let (code, output) = run_child(child, "output-after-signal", [Await("ready"), Send(kind)])
    assert_in_order(output, ["hook=a.stop"] + lines + ["end", "hook=b.stopped", "hook=a.stopped"])
    assert_eq(code, exit_code, msg=child.label())
  }
}

///|
/// A timer that a service leaves open must not keep a js process running
/// after a graceful signal stop. A native process always ends through libc
/// `exit`, so this test also runs the native child.
async test "a timer left open does not keep the process running after a signal stop" {
  for child in children(native=true) {
    let (kind, name, exit_code) = sendable_kinds()[0]
    let (code, output) = run_child(child, "linger", [Await("ready"), Send(kind)])
    assert_in_order(output, ["reason=Signal(\{name})", "hook=a.stopped"])
    assert_eq(code, exit_code, msg="\{child.label()}\n\{output}")
  }
}
