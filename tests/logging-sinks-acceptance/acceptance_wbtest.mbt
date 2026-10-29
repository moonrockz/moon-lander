///|
/// The tests start child processes that run a scenario of
/// `logging-sinks-scenarios`. A native child is this test binary again, with
/// only the helper test (the first test in this file). A js child is the
/// program `logging-sinks-program` under Node.js or Bun. The parent reads the
/// output of the child, and the log files after the child ends.
let scenario_var : String = "LANDER_LOGGING_SCENARIO"

///|
/// The absolute temporary directory of one child.
let dir_var : String = "LANDER_LOGGING_DIR"

///|
/// The path of the built js program. `mise run check:logging-sinks` sets it.
/// Without it, only the native child runs.
let js_program_var : String = "LANDER_LOGGING_JS_PROGRAM"

///|
/// The js runtimes to test, separated by commas, for example `node,bun`.
let js_runtimes_var : String = "LANDER_LOGGING_JS_RUNTIMES"

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
  @scenarios.run(scenario, @env.get_env_var(dir_var).unwrap_or(""))
}

///|
priv enum Child {
  Native
  NativeProgram(String)
  Js(runtime~ : String, program~ : String)
  Worker(launcher~ : String, program~ : String)
}

///|
fn Child::label(self : Child) -> String {
  match self {
    Native | NativeProgram(_) => "native"
    Js(runtime~, ..) => runtime
    Worker(..) => "node worker"
  }
}

///|
priv enum Step {
  Await(String)
  Send(Int)
}

///|
/// Keep the child phase and streamed output when the timeout cancels a read.
priv enum ChildPhase {
  Starting
  Awaiting(String)
  Signalling(Int)
  ReadingOutput
  WaitingForExit
} derive(Debug)

///|
/// The result of one child: exit code, standard output and standard error,
/// with `\r\n` as `\n`.
priv struct Ran {
  code : Int
  out : String
  err : String
}

///|
/// Start `child` in `scenario` with the log directory `dir`, do the steps in
/// order, and read the rest of both outputs. Every wait is bounded.
async fn run_child(
  child : Child,
  scenario : String,
  dir : String,
  steps : Array[Step],
) -> Ran {
  let (command, args) = match child {
    NativeProgram(program) => (program, [])
    Native => {
      let args = @env.args()
      guard args.length() > 1 && args[1].split(":").next() is Some(file) else {
        fail("unexpected test arguments: " + args.join(" "))
      }
      (args[0], ["\{file}:0-1"])
    }
    // See tests/console-signal-acceptance for the reason of this flag.
    Js(runtime="node", program~) =>
      ("node", ["--preserve-symlinks-main", program])
    Js(runtime~, program~) => (runtime, [program])
    Worker(launcher~, program~) =>
      ("node", ["--preserve-symlinks-main", launcher, program])
  }
  let output = StringBuilder()
  let phase = Ref(ChildPhase::Starting)
  try @async.with_timeout(30000, () => {
    @async.with_task_group(group => {
      let (reader, writer) = @process.read_from_process()
      let (err_reader, err_writer) = @process.read_from_process()
      let process = @process.spawn(
        group,
        command,
        args,
        extra_env=Map::from_array([(scenario_var, scenario), (dir_var, dir)]),
        stdout=writer,
        stderr=err_writer,
      )
      writer.close()
      err_writer.close()
      let err_task = group.spawn(() => err_reader.read_all().text())
      let received : @async.Queue[String?] = @async.Queue(kind=Unbounded)
      let stdout = group.spawn(() => {
        while reader.read_until("\n") is Some(line) {
          let line = line.trim_end(chars="\r").to_owned()
          output.write_string(line + "\n")
          received.put(Some(line))
        }
        received.put(None)
      })
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
            guard sent == 0 else {
              fail("sending kind \{kind} failed: \{sent}")
            }
          }
        }
      }
      phase.val = ReadingOutput
      stdout.wait()
      phase.val = WaitingForExit
      let code = process.wait()
      let normalize = (text : String) => text.replace_all(old="\r\n", new="\n")
      { code, out: normalize(output.to_string()), err: normalize(err_task.wait()) }
    })
  }) catch {
    @async.TimeoutError => fail("\{child.label()} \{scenario} timed out in \{@debug.to_string(phase.val)}; captured stdout:\n\{output}")
    other => raise other
  }
}

///|
/// The native child and, when `mise run check:logging-sinks` gives the
/// program, a js child for each runtime.
fn children() -> Array[Child] {
  let children = [Native]
  guard @env.get_env_var(js_program_var) is Some(program) else {
    return children
  }
  let runtimes = @env.get_env_var(js_runtimes_var).unwrap_or("node")
  for runtime in runtimes.split(",") {
    children.push(Js(runtime=runtime.to_owned(), program~))
  }
  children
}

///|
/// The kinds that this platform can send to one child process, with the
/// reason and the exit code. Windows sends only `CTRL_BREAK_EVENT` to one
/// process group.
fn sendable_kinds() -> Array[(Int, Int)] {
  match @async.platform {
    Windows => [(3, 131)]
    _ => [(1, 130), (2, 143), (3, 131)]
  }
}

///|
/// The lines of `text`, without empty lines.
fn lines(text : String) -> Array[String] {
  text.split("\n").map(line => line.to_owned()).filter(line => !line.is_empty()).collect()
}

///|
/// Check that a line of `text` ends with each of `suffixes`, in this order.
fn assert_suffixes_in_order(
  text : String,
  suffixes : Array[String],
  label : String,
) -> Unit raise {
  let actual = lines(text)
  let mut at = 0
  for suffix in suffixes {
    while at < actual.length() && !actual[at].has_suffix(suffix) {
      at += 1
    }
    guard at < actual.length() else {
      fail("\{label}: missing or out of order: \{suffix}\n\{text}")
    }
    at += 1
  }
}

///|
/// Check that no line of `text` ends with `suffix`.
fn assert_no_suffix(text : String, suffix : String, label : String) -> Unit raise {
  for line in lines(text) {
    guard !line.has_suffix(suffix) else {
      fail("\{label}: unexpected line: \{suffix}\n\{text}")
    }
  }
}

///|
/// A new empty temporary directory, with `/` separators.
async fn temp_dir(label : String) -> String {
  @fs.tmpdir(prefix="lander-logging-\{label}").replace_all(old="\\", new="/")
}

///|
/// The names in `dir`, sorted.
async fn names(dir : String) -> Array[String] {
  @fs.readdir(dir, include_hidden=true, sort=true)
}

///|
/// The text of each file in `dir` whose name has `prefix` and `suffix`,
/// joined in name order.
async fn read_files(dir : String, prefix : String, suffix : String) -> String {
  let text = StringBuilder()
  for name in names(dir) {
    if name.has_prefix(prefix) && name.has_suffix(suffix) {
      text.write_string(@fs.read_file(dir + "/" + name).text())
    }
  }
  text.to_string().replace_all(old="\r\n", new="\n")
}

///|
fn assert_no_marker(entries : Array[String], label : String) -> Unit raise {
  for name in entries {
    guard !name.has_suffix(".lock") else {
      fail("\{label}: the ownership marker \{name} stayed")
    }
  }
}

///|
let standalone_console : Array[String] = [
  "INF] Loaded 3 files from src", "WRN] Unicode é 😀 ✓", "ERR] Compilation failed for app.mbt",
  "    CompilerError: Unknown identifier calculate_total", "      at app.mbt:42",
]

///|
async test "hosted session close drains before telemetry and remains idempotent" {
  for child in children() {
    for (scenario, code) in [("session-ordered", 0), ("session-signal", 143)] {
      let dir = temp_dir(scenario)
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, scenario, dir, [])
      let label = child.label() + " " + scenario
      assert_eq(ran.code, code, msg=label + "\n" + ran.out + ran.err)
      assert_suffixes_in_order(ran.out, [
        "telemetry=start", "diagnostic=start", "diagnostic=stop",
        "diagnostic.last", "diagnostic=closed", "telemetry=flushed-after-drain", "telemetry=stop",
      ], label)
      if code == 143 {
        assert_true(ran.out.contains("reason=Signal(Terminate)"), msg=ran.out)
      }
      let text = read_files(dir, "session-", ".log")
      assert_suffixes_in_order(text, ["telemetry.start", "diagnostic.start", "command", "diagnostic.last"], label)
      assert_false(text.contains("late-after-close") || text.contains("late-stopped"), msg=text)
      assert_no_marker(names(dir), label)
      assert_eq(ran.out.split("diagnostic=closed\n").count() - 1, 1, msg=ran.out)
    }
  }
}

///|
async test "session-aware finalization drains after startup failure and skipped or timed-out stop hooks" {
  for child in children() {
    for scenario in ["session-start-failure", "session-skipped", "session-timed-stop"] {
      let dir = temp_dir(scenario)
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, scenario, dir, [])
      let label = child.label() + " " + scenario
      assert_eq(ran.code, 1, msg=label + "\n" + ran.out + ran.err)
      let text = read_files(dir, "session-", ".log")
      assert_true(text.contains("diagnostic.start"), msg=text)
      assert_false(ran.out.contains("diagnostic=closed"), msg=ran.out)
      if scenario == "session-start-failure" {
        assert_false(text.contains("command"), msg=text)
        assert_true(ran.err.contains("diagnostic startup failed"), msg=ran.err)
      } else {
        assert_true(text.contains("command"), msg=text)
        assert_true(ran.err.contains("Shutdown"), msg=ran.err)
      }
      assert_no_marker(names(dir), label)
    }
  }
}

///|
async test "the logger-only bridge forwards a consuming probe through its final drain" {
  for child in children() {
    let dir = temp_dir("probe-legacy")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "probe-legacy", dir, [])
    assert_eq(ran.code, 130, msg=ran.out + ran.err)
    let text = read_files(dir, "legacy-", ".log")
    assert_suffixes_in_order(text, ["legacy.accepted", "reason=Signal(Interrupt)"], child.label())
    assert_no_marker(names(dir), child.label())
  }
}

///|
async test "post-close failure reports bypass the logger and signal codes survive sink failures" {
  for child in children() {
    let dir = temp_dir("late-failure")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "session-late-failure", dir, [])
    assert_eq(ran.code, 1, msg=ran.out + ran.err)
    assert_suffixes_in_order(ran.out, ["diagnostic=closed", "telemetry=flushed-after-drain", "telemetry=stop"], child.label())
    assert_true(ran.err.contains("telemetry flush failed"), msg=ran.err)
    let text = read_files(dir, "session-", ".log")
    assert_true(text.contains("diagnostic.last"), msg=text)
    assert_false(text.contains("telemetry flush failed"), msg=text)
    assert_no_marker(names(dir), child.label())
    @fs.write_file(dir + "/blocker", "regular file")
    let signal = run_child(child, "probe-failure", dir, [])
    assert_eq(signal.code, 130, msg=signal.out + signal.err)
    assert_true(signal.err.contains("logging: create directory failed"), msg=signal.err)
    assert_true(signal.out.contains("reason=Signal(Interrupt)"), msg=signal.out)
  }
}

///|
async test "real parent signals stop a non-yielding logging worker and drain before telemetry" {
  guard !(@async.platform is Windows) else { return }
  guard @env.get_env_var("LANDER_LOGGING_WORKER_LAUNCHER") is Some(launcher) else { return }
  guard @env.get_env_var("LANDER_LOGGING_WORKER_PROGRAM") is Some(program) else { fail("missing logging worker") }
  for (kind, name, code) in [(1, "Interrupt", 130), (2, "Terminate", 143)] {
    let dir = temp_dir("logging-worker")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(Worker(launcher~, program~), "session-poll", dir, [Await("ready"), Send(kind)])
    assert_eq(ran.code, code, msg=ran.out + ran.err)
    // Readiness uses a control channel; buffered worker stdout can arrive later.
    assert_true(ran.out.contains("worker-stdout-pending"), msg=ran.out)
    assert_eq(ran.out.split("ready\n").count() - 1, 1, msg=ran.out)
    assert_suffixes_in_order(ran.out, [
      "diagnostic=stop", "reason=Signal(\{name})", "polled=true",
      "diagnostic=closed", "telemetry=flushed-after-drain", "telemetry=stop", "owner-listeners=intact",
    ], "logging worker")
    let text = read_files(dir, "session-", ".log")
    assert_suffixes_in_order(text, ["command", "diagnostic.last"], "logging worker")
    assert_no_marker(names(dir), "logging worker")
  }
}

///|
async test "a standalone session writes the console and both files, then drains before exit" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("standalone")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "standalone", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_suffixes_in_order(
      ran.out,
      standalone_console +
      ["closed accepted=3 queue_full=0 failed=false written=3,3,3"],
      label,
    )
    let text = read_files(dir, "acme-", ".log")
    assert_suffixes_in_order(text, standalone_console, label + " text file")
    for line in lines(text) {
      guard !line.contains("\u{1b}") else { fail("\{label}: color in a file") }
    }
    let jsonl = read_files(dir, "acme-", ".jsonl")
    let records = lines(jsonl)
    assert_eq(records.length(), 3, msg=label + "\n" + jsonl)
    let decoded = records.map(line => @json.parse(line))
    guard decoded[1] is { "message": String(message), "properties": [{ "name": "Text", "value": String(value), .. }], .. } else {
      fail("\{label}: unexpected record \{records[1]}")
    }
    assert_eq(message, "Unicode é 😀 ✓")
    assert_eq(value, "é 😀 ✓")
    guard decoded[2] is { "error": String(error), "level": "Error", .. } else {
      fail("\{label}: unexpected record \{records[2]}")
    }
    assert_eq(
      error, "CompilerError: Unknown identifier calculate_total\n  at app.mbt:42",
    )
    guard decoded[0] is { "schemaVersion": 1, "properties": [{ "name": "Count", "value": 3, .. }, { "name": "Path", "value": "src", .. }], .. } else {
      fail("\{label}: unexpected record \{records[0]}")
    }
    assert_no_marker(names(dir), label)
  }
}

///|
async test "public rolling files retain approved object properties and the array default" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("object-properties")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "object-properties", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_true(ran.out.contains("closed accepted=4 queue_full=0 failed=false written=4,4,4"), msg=ran.out)
    assert_no_marker(names(dir), label)
    for prefix in ["array", "named"] {
      let files = names(dir).filter(name => name.has_prefix(prefix) && name.has_suffix(".jsonl"))
      assert_eq(files.length(), 4, msg=files.join(","))
      for name in files {
        assert_eq(lines(@fs.read_file(dir + "/" + name).text()).length(), 1)
      }
    }
    let named = lines(read_files(dir, "named", ".jsonl")).map(line => @json.parse(line))
    let expected : Array[Json] = [
      { "path": "/repo/morphir.toml", "array": [1, Json::null(), { "nested": true }], "object": { "items": [false, 2] }, "nothing": Json::null(), "flag": true, "number": 2.5 },
      { "path": { "nested": [true, 2] }, "level": false, "command": "project.list", "duplicateProperties": "inside", "properties": "safe" },
      { "value": Json::null(), "text": "é 😀\n\r\u{1b}\"\\" },
      {},
    ]
    let history : Array[Json?] = [
      None,
      Some({ "path": [Json::null(), [1, Json::null()], { "nested": [true, 2] }], "level": ["event", false] }),
      Some({ "value": [1, Json::null()] }),
      None,
    ]
    for index, record in named {
      guard record is Object(fields) else { fail("not an object") }
      assert_eq(fields.get("schemaVersion"), Some(2))
      assert_eq(fields.get("level"), Some("Information"))
      assert_eq(fields.get("properties"), Some(expected[index]), msg=label)
      assert_eq(fields.get("duplicateProperties"), history[index], msg=label)
    }
    let legacy = lines(read_files(dir, "array", ".jsonl")).map(line => @json.parse(line))
    for index, record in legacy {
      guard record is Object(fields) else { fail("not an object") }
      assert_eq(fields.get("schemaVersion"), Some(1))
      assert_eq(fields.get("duplicateProperties"), None)
      guard fields.get("properties") is Some(Array(entries)) else { fail("default ceased to be an array") }
      assert_eq(entries.length(), [6, 8, 3, 0][index])
    }
    guard legacy[1] is Object(fields) else { fail("not an object") }
    assert_eq(fields.get("properties"), Some([
      { "name": "path", "value": Json::null() }, { "name": "level", "value": "event" },
      { "name": "path", "value": [1, Json::null()] }, { "name": "command", "value": "project.list" },
      { "name": "path", "value": { "nested": [true, 2] } }, { "name": "level", "value": false },
      { "name": "duplicateProperties", "value": "inside" }, { "name": "properties", "value": "safe" },
    ]))
    let restarted = run_child(child, "object-properties", dir, [])
    assert_eq(restarted.code, 0, msg=restarted.out + restarted.err)
    assert_no_marker(names(dir), label)
    let after = lines(read_files(dir, "named", ".jsonl"))
    assert_eq(after.length(), 8)
    for index, line in after {
      guard @json.parse(line) is Object(fields) else { fail("not an object") }
      assert_eq(fields.get("schemaVersion"), Some(2))
      assert_eq(fields.get("properties"), Some(expected[index % 4]))
      assert_eq(fields.get("duplicateProperties"), history[index % 4])
    }
  }
}

///|
async test "an ownership marker left by a crash stops only its file set" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("marker")
    defer @fs.rmdir(dir, recursive=true)
    @fs.write_file(dir + "/acme.log.lock", "")
    let ran = run_child(child, "standalone", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_suffixes_in_order(
      ran.out,
      standalone_console +
      ["closed accepted=3 queue_full=0 failed=true written=3,0,3"],
      label,
    )
    let entries = names(dir)
    assert_true(entries.contains("acme.log.lock"), msg=label)
    assert_false(
      entries.iter().any(name => name.has_suffix(".log")),
      msg="\{label}: \{entries.join(", ")}",
    )
    assert_eq(lines(read_files(dir, "acme-", ".jsonl")).length(), 3)
  }
}

///|
async test "a session with no file event creates no directory, marker or file" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("quiet")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "quiet", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_suffixes_in_order(
      ran.out,
      ["INF] only on the console", "closed accepted=1 queue_full=0 failed=false written=1,0"],
      label,
    )
    assert_eq(names(dir), [], msg=label)
  }
}

///|
async test "a log directory without write permission is a visible ownership failure" {
  // Windows has no POSIX mode bits for directories.
  guard !(@async.platform is Windows) else { return }
  for child in children() {
    let label = child.label()
    let dir = temp_dir("denied")
    defer @fs.rmdir(dir, recursive=true)
    @fs.chmod(dir, 0o555)
    defer @fs.chmod(dir, 0o755)
    let ran = run_child(child, "standalone", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_suffixes_in_order(
      ran.out,
      ["closed accepted=3 queue_full=0 failed=true written=3,0,0"],
      label,
    )
    assert_eq(names(dir), [], msg=label)
  }
}

///|
async test "a large volume reaches the pipe and the file completely and in order" {
  let expected = Array::makei(@scenarios.volume_events, index => "INF] " +
    @scenarios.volume_line(index))
  for child in children() {
    let label = child.label()
    let dir = temp_dir("volume")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "volume", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.err}")
    let summary = "closed accepted=\{@scenarios.volume_events} queue_full=0 failed=false"
    assert_suffixes_in_order(ran.out, expected, label)
    assert_true(ran.out.contains(summary), msg=label)
    let text = read_files(dir, "volume-", ".log")
    assert_eq(lines(text).length(), @scenarios.volume_events, msg=label)
    assert_suffixes_in_order(text, expected, label + " file")
  }
}

///|
async test "a configuration failure before any hook still reaches the final drain" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("config")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "host-config-failure", dir, [])
    assert_eq(ran.code, 2, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_no_suffix(ran.out, "INF] hook=a.starting", label)
    assert_true(
      lines(ran.out).iter().any(line => line.contains("ERR] logging-host: ")),
      msg="\{label}\n\{ran.out}",
    )
    assert_true(
      read_files(dir, "host-", ".log").contains("ERR] logging-host: "),
      msg=label,
    )
  }
}

///|
let start_hooks : Array[String] = [
  "INF] hook=a.starting", "INF] hook=a.start", "INF] hook=a.started",
]

///|
let stop_hooks : Array[String] = [
  "INF] hook=b.stopping", "INF] hook=a.stopping", "INF] hook=b.stop", "INF] hook=a.stop",
  "INF] hook=b.stopped", "INF] hook=a.stopped",
]

///|
async test "a hosted run logs every hook and drains before the driver ends the process" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("host")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "host-clean", dir, [])
    assert_eq(ran.code, 0, msg="\{label}\n\{ran.out}\n\{ran.err}")
    let expected = start_hooks + ["INF] command"] + stop_hooks
    assert_suffixes_in_order(ran.out, expected, label)
    assert_suffixes_in_order(read_files(dir, "host-", ".log"), expected, label)
    assert_no_marker(names(dir), label)
  }
}

///|
async test "the default report goes through the logger before the final drain" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("usage")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "host-usage", dir, [])
    assert_eq(ran.code, 2, msg="\{label}\n\{ran.out}\n\{ran.err}")
    let expected = start_hooks + stop_hooks + ["ERR] logging-host: bad option"]
    assert_suffixes_in_order(ran.out, expected, label)
    assert_suffixes_in_order(read_files(dir, "host-", ".log"), expected, label)
    // No console destination writes to standard error here, so the bridge
    // also writes the plain report line there, as the host does without it.
    assert_eq(lines(ran.err), ["logging-host: bad option"])
  }
}

///|
async test "a start failure still reaches the final drain" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("start")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "host-start-failure", dir, [])
    assert_eq(ran.code, 1, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_suffixes_in_order(
      ran.out,
      ["INF] hook=a.starting", "INF] hook=a.start"],
      label,
    )
    assert_no_suffix(ran.out, "INF] command", label)
    assert_true(
      lines(ran.out).iter().any(line => line.contains("ERR] logging-host: ")),
      msg=ran.out,
    )
    assert_true(
      read_files(dir, "host-", ".log").contains("ERR] logging-host: "),
      msg=label,
    )
  }
}

///|
async test "a shutdown timeout skips hooks but not the final drain" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("timeout")
    defer @fs.rmdir(dir, recursive=true)
    let ran = run_child(child, "host-timeout", dir, [])
    assert_eq(ran.code, 1, msg="\{label}\n\{ran.out}\n\{ran.err}")
    let expected = ["INF] slow", "ERR] logging-host: Shutdown timed out after 200ms"]
    assert_suffixes_in_order(ran.out, expected, label)
    assert_no_suffix(ran.out, "INF] hook=b.stop.end", label)
    assert_suffixes_in_order(read_files(dir, "host-", ".log"), expected, label)
    assert_no_marker(names(dir), label)
  }
}

///|
async test "a first signal stops gracefully and the stop hook logs reach the outputs" {
  for child in children() {
    let label = child.label()
    for case in sendable_kinds() {
      let (kind, exit_code) = case
      let dir = temp_dir("signal")
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, "host-wait", dir, [Await("INF] ready"), Send(kind)])
      assert_eq(ran.code, exit_code, msg="\{label} \{kind}\n\{ran.out}\n\{ran.err}")
      let expected = start_hooks + ["INF] ready"] + stop_hooks
      assert_suffixes_in_order(ran.out, expected, label)
      assert_no_suffix(ran.out, "INF] command must be cancelled", label)
      assert_suffixes_in_order(read_files(dir, "host-", ".log"), expected, label)
      assert_no_marker(names(dir), label)
    }
  }
}

///|
async test "a second signal still ends the process at once" {
  for child in children() {
    let label = child.label()
    for case in sendable_kinds() {
      let (kind, exit_code) = case
      let dir = temp_dir("second")
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, "host-slow-stop", dir, [
        Await("INF] ready"),
        Send(kind),
        Await("INF] slow"),
        Send(kind),
      ])
      assert_eq(ran.code, exit_code, msg="\{label} \{kind}\n\{ran.out}\n\{ran.err}")
      assert_no_suffix(ran.out, "INF] hook=b.stop.end", label)
      assert_no_suffix(ran.out, "INF] hook=a.stopped", label)
    }
  }
}

///|
async test "a failed file destination keeps the console and gives exit code 1" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("failure")
    defer @fs.rmdir(dir, recursive=true)
    @fs.write_file(dir + "/blocker", "a file, not a directory\n")
    let ran = run_child(child, "file-failure", dir, [])
    assert_eq(ran.code, 1, msg="\{label}\n\{ran.out}\n\{ran.err}")
    assert_suffixes_in_order(ran.out, start_hooks + ["INF] command"] + stop_hooks, label)
    assert_true(
      ran.err.contains("logging: create directory failed for files "),
      msg="\{label}\n\{ran.err}",
    )
  }
}

///|
/// The text of `text` without ANSI SGR sequences.
fn strip_styles(text : String) -> String {
  let out = StringBuilder()
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '\u{1b}' && i + 1 < chars.length() && chars[i + 1] == '[' {
      i += 2
      while i < chars.length() && chars[i] != 'm' {
        i += 1
      }
      i += 1
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}

///|
/// The owned regular text files of `Fanout` in `dir`: `acme.log` and
/// `acme_NNN.log`. A link is not counted.
async fn size_rolls(dir : String) -> Array[String] {
  let rolls = []
  for name in names(dir) {
    let digits = match name.strip_prefix("acme_") {
      Some(rest) =>
        match rest.strip_suffix(".log") {
          Some(number) =>
            !number.is_empty() && number.iter().all(char => char >= '0' && char <= '9')
          None => false
        }
      None => false
    }
    guard name == "acme.log" || digits else { continue }
    if @fs.kind(dir + "/" + name, follow_symlink=false) is Regular {
      rolls.push(name)
    }
  }
  rolls
}

///|
/// Unrelated entries of `Fanout` with names like the owned files.
let unrelated : Array[String] = [
  "acme-old.log", "acme_001.log.bak", "acmex.log", "acme_x.log",
]

///|
async test "fan-out, filtering, burst drops, rolling, retention and restart through the public API" {
  for child in children() {
    let label = child.label()
    let dir = temp_dir("fanout")
    defer @fs.rmdir(dir, recursive=true)
    for name in unrelated {
      @fs.write_file(dir + "/" + name, "unrelated\n")
    }
    @fs.mkdir(dir + "/acme-20261001.jsonl")
    // A link with an owned name is never written or deleted. Windows needs a
    // privilege for links, so only Linux and macOS add one.
    let outside = temp_dir("outside")
    defer @fs.rmdir(outside, recursive=true)
    @fs.write_file(outside + "/target.txt", "outside\n")
    let link = !(@async.platform is Windows)
    if link {
      @fs.symlink(target=outside + "/target.txt", dir + "/acme.log")
    }
    let accepted = 3 + @scenarios.burst_limit
    let dropped = @scenarios.burst_events - @scenarios.burst_limit
    let summary = "closed accepted=\{accepted} queue_full=\{dropped} failed=false"
    let first = run_child(child, "fanout", dir, [])
    assert_eq(first.code, 0, msg="\{label}\n\{first.out}\n\{first.err}")
    assert_true(first.out.contains("\u{1b}["), msg="\{label}: no Literate styles")
    let plain = strip_styles(first.out)
    assert_suffixes_in_order(
      plain,
      [
        "[23:59:58.000Z INF] Loaded 3 files from src", "[00:00:01.000Z INF] Next day 28 with true and null",
        "[00:00:01.000Z INF] burst 0", "[00:00:01.000Z INF] burst \{@scenarios.burst_limit - 1}",
      ],
      label,
    )
    assert_no_suffix(plain, "Only in the text file", label)
    assert_no_suffix(plain, "burst \{@scenarios.burst_limit}", label)
    assert_true(
      lines(plain).iter().any(line => line.contains(summary)),
      msg="\{label}\n\{plain}",
    )
    let entries = names(dir)
    assert_no_marker(entries, label)
    for name in unrelated {
      assert_eq(@fs.read_file(dir + "/" + name).text(), "unrelated\n")
    }
    assert_true(@fs.kind(dir + "/acme-20261001.jsonl") is Directory)
    if link {
      assert_true(@fs.kind(dir + "/acme.log", follow_symlink=false) is SymLink)
      assert_eq(@fs.read_file(outside + "/target.txt").text(), "outside\n")
    }
    // The daily JSON Lines files keep the captured times of both days.
    let day_one = @fs.read_file(dir + "/acme-20261027.jsonl").text()
    assert_eq(lines(day_one).length(), 1, msg=day_one)
    guard @json.parse(lines(day_one)[0]) is { "timestamp": "2026-10-27T23:59:58.000Z", "message": "Loaded 3 files from src", .. } else {
      fail("\{label}: \{day_one}")
    }
    let day_two = lines(@fs.read_file(dir + "/acme-20261028.jsonl").text())
    assert_eq(day_two.length(), 1 + @scenarios.burst_limit)
    guard @json.parse(day_two[0]) is { "properties": [{ "name": "Day", "value": 28, .. }, { "name": "Flag", "value": true, .. }, { "name": "Nothing", "value": Null, .. }], .. } else {
      fail("\{label}: \{day_two[0]}")
    }
    // Size rolls of 400 bytes keep the newest 3 text files.
    let rolls = size_rolls(dir)
    assert_eq(rolls.length(), 3, msg="\{label}: \{entries.join(", ")}")
    let text = read_files(dir, "acme_", ".log")
    assert_true(
      text.contains(
        "\{@scenarios.burst_limit - 1}\n",
      ),
      msg=text,
    )
    for name in rolls {
      let size = @fs.file_size(dir + "/" + name)
      guard size <= 400L else { fail("\{label}: \{name} has \{size} bytes") }
    }
    // A restart appends to the files of the same set and continues the sequence.
    let second = run_child(child, "fanout", dir, [])
    assert_eq(second.code, 0, msg="\{label}\n\{second.out}\n\{second.err}")
    let restarted = names(dir)
    assert_no_marker(restarted, label)
    if link {
      assert_true(@fs.kind(dir + "/acme.log", follow_symlink=false) is SymLink)
      assert_eq(@fs.read_file(outside + "/target.txt").text(), "outside\n")
    }
    assert_eq(
      lines(@fs.read_file(dir + "/acme-20261027.jsonl").text()).length(),
      2,
    )
    let after = size_rolls(dir)
    assert_eq(after.length(), 3, msg="\{label}: \{restarted.join(", ")}")
    guard after.last() is Some(newest) && rolls.last() is Some(older) else {
      fail("no rolls")
    }
    assert_true(newest > older, msg="\{label}: \{older} then \{newest}")
  }
}

///|
async test "completion reports a pending signal before any hook or command" {
  let cases = completion_children()
  for child in cases {
    for (scenario, code) in [("completion-early-int", 130), ("completion-early-term", 143)] {
      let dir = temp_dir(scenario)
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, scenario, dir, [])
      assert_eq(ran.code, code, msg=ran.out + ran.err)
      assert_eq(ran.out.trim(), "{\"reason\":\"signal\",\"exit_code\":\{code},\"hooks\":0,\"commands\":0,\"closed\":true}", msg=child.label() + " stdout=" + ran.out + " stderr=" + ran.err)
      assert_true(read_files(dir, "completion-", ".log").contains("factory.accepted"))
      assert_no_marker(names(dir), child.label())
    }
  }
}

///|
/// Real executables only: a reused moon test binary adds protocol stdout.
fn completion_children() -> Array[Child] raise {
  let cases = children().filter(child => !(child is Native))
  if @env.get_env_var("LANDER_LOGGING_NATIVE_PROGRAM") is Some(program) {
    cases.push(NativeProgram(program))
  } else {
    guard @env.get_env_var(js_program_var) is None else { fail("missing native completion program") }
  }
  cases
}

///|
async test "completion retains real lifecycle outcomes and closes before reporting" {
  for child in completion_children() {
    for (scenario, exit_code, reason, hooks, commands, selected) in [
      ("completion-startup", 143, "signal", 1, 0, 143),
      ("completion-running", 130, "signal", 2, 1, 130),
      ("completion-clean", 0, "completed", 2, 1, 0),
      ("completion-failure", 1, "failed", 2, 1, 1),
      ("completion-config", 2, "start-failed", 0, 0, 2),
      ("completion-timeout", 1, "completed", 2, 1, 1),
      ("completion-closed", 0, "completed", 2, 1, 0),
      ("completion-throws", 1, "completed", 2, 1, 0),
      ("completion-throws-int", 130, "signal", 0, 0, 130),
      ("completion-throws-term", 143, "signal", 0, 0, 143),
    ] {
      let dir = temp_dir(scenario)
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, scenario, dir, [])
      let label = child.label() + " " + scenario + "\n" + ran.out + ran.err
      assert_eq(ran.code, exit_code, msg=label)
      guard @json.parse(ran.out) is Object(fields) else { fail(label) }
      assert_eq(fields.get("reason"), Some(Json::string(reason)), msg=label)
      assert_eq(fields.get("exit_code"), Some(Json(selected)), msg=label)
      assert_eq(fields.get("hooks"), Some(Json(hooks)), msg=label)
      assert_eq(fields.get("commands"), Some(Json(commands)), msg=label)
      assert_eq(fields.get("closed"), Some(true), msg=label)
      assert_eq(ran.out.trim().split("\n").count(), 1, msg=label)
      let files = read_files(dir, "completion-", ".log")
      assert_true(files.contains("factory.accepted"), msg=label)
      if scenario == "completion-running" { assert_true(files.contains("command.cleanup"), msg=label) }
      assert_no_marker(names(dir), label)
    }
  }
}

///|
async test "logger-only completion reports an early signal exactly once" {
  for child in completion_children() {
    for (scenario, code) in [("completion-legacy-int", 130), ("completion-legacy-term", 143)] {
      let dir = temp_dir(scenario)
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, scenario, dir, [])
      assert_eq(ran.code, code, msg=ran.out + ran.err)
      assert_eq(ran.out.trim(), "{\"reason\":\"signal\",\"exit_code\":\{code},\"hooks\":0,\"commands\":0,\"legacy\":true}", msg=child.label() + ran.out + ran.err)
      assert_true(read_files(dir, "completion-", ".log").contains("factory.accepted"))
      assert_no_marker(names(dir), child.label())
    }
  }
}

///|
async test "omitting completion preserves empty stdout and final drain on early signals" {
  for child in completion_children() {
    for (scenario, code) in [("completion-default-int", 130), ("completion-default-term", 143)] {
      let dir = temp_dir(scenario)
      defer @fs.rmdir(dir, recursive=true)
      let ran = run_child(child, scenario, dir, [])
      assert_eq(ran.code, code, msg=ran.out + ran.err)
      assert_eq(ran.out, "", msg=child.label())
      assert_true(read_files(dir, "completion-", ".log").contains("factory.accepted"))
      assert_no_marker(names(dir), child.label())
    }
  }
}
