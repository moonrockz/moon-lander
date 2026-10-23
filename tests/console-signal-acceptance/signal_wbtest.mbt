///|
/// The tests start their own test binary again as a child process. This env
/// variable selects what the helper test (the first test in this file) does in
/// the child. Without it, the helper test passes at once.
let helper_mode_var : String = "LANDER_CONSOLE_HELPER"

///|
/// Send the stop signal `kind` (1 Interrupt, 2 Terminate, 3 Quit) to the
/// process `pid` through `send.c`. Gives 0 on success.
extern "C" fn send_signal(pid : Int, kind : Int) -> Int = "lander_test_send_signal"

///|
async fn write_line(text : String) -> Unit {
  @stdio.stdout.write(text + "\n")
}

///|
fn kind_name(kind : @console.SignalKind?) -> String {
  match kind {
    Some(Interrupt) => "Interrupt"
    Some(Terminate) => "Terminate"
    Some(Quit) => "Quit"
    None => "none"
  }
}

///|
/// Index 0 of this file. `report`: install the handlers, keep the async event
/// loop busy, and report the first signal. `spin`: install the handlers and run
/// a loop with no suspension point and no stop check, so only a second signal
/// can end the process.
async test "helper: the child process body" {
  match @env.get_env_var(helper_mode_var) {
    Some("report") => {
      assert_true(@console.install())
      write_line("ready")
      while !@console.stop_requested() {
        @async.sleep(10)
      }
      @async.sleep(50)
      write_line("kind=" + kind_name(@console.signal_kind()))
    }
    Some("spin") => {
      assert_true(@console.install())
      write_line("ready")
      let count = Ref(0UL)
      while true {
        count.val = count.val + 1UL
      }
    }
    _ => ()
  }
}

///|
/// Start this test binary again with only the helper test, in `mode`; wait
/// until it is ready; send `kind` `times` times; and give its exit code and
/// the rest of its output.
async fn run_helper(mode : String, kind : Int, times~ : Int) -> (Int, String) {
  let args = @env.args()
  guard args.length() > 1 && args[1].split(":").next() is Some(file) else {
    fail("unexpected test arguments: " + args.join(" "))
  }
  @async.with_timeout(20000, () => {
    @async.with_task_group(group => {
      let (reader, writer) = @process.read_from_process()
      let child = @process.spawn(
        group,
        args[0],
        ["\{file}:0-1"],
        extra_env=Map::from_array([(helper_mode_var, mode)]),
        stdout=writer,
      )
      writer.close()
      guard reader.read_until("ready") is Some(_) else {
        fail("the helper did not start")
      }
      for _ in 0..<times {
        let sent = send_signal(child.pid, kind)
        guard sent == 0 else { fail("sending kind \{kind} failed: \{sent}") }
        @async.sleep(200)
      }
      let rest = reader.read_all().text()
      (child.wait(), rest)
    })
  })
}

///|
/// The kinds that this platform can send to one child process.
fn sendable_kinds() -> Array[(Int, String, Int)] {
  match @async.platform {
    Windows => [(3, "Quit", 131)]
    _ => [(1, "Interrupt", 130), (2, "Terminate", 143), (3, "Quit", 131)]
  }
}

///|
async test "a first signal sets the stop request and its identity while the event loop runs" {
  for case in sendable_kinds() {
    let (kind, name, _) = case
    let (code, output) = run_helper("report", kind, times=1)
    assert_true(output.contains("kind=" + name), msg=output)
    assert_eq(code, 0, msg=output)
  }
}

///|
async test "a second signal ends a loop with no suspension point with the mapped code" {
  for case in sendable_kinds() {
    let (kind, _, exit_code) = case
    let (code, output) = run_helper("spin", kind, times=2)
    assert_eq(code, exit_code, msg=output)
  }
}
