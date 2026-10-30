///|
#borrow(runner, wasm, node, owner)
extern "C" fn start_console(
  runner : String, runner_length : Int,
  wasm : String, wasm_length : Int,
  node : String, node_length : Int,
  owner : String, owner_length : Int,
  mode : Int,
) -> Int = "lander_moonx_console_start"

///|
extern "C" fn resume_console() -> Int = "lander_moonx_console_resume"

///|
extern "C" fn send_event(kind : Int) -> Int = "lander_moonx_console_event"

///|
extern "C" fn last_error() -> Int = "lander_moonx_console_error"

///|
extern "C" fn close_console() -> Unit = "lander_moonx_console_close"

///|
extern "C" fn process_running(pid : Int) -> Int = "lander_moonx_process_running"

///|
priv enum ConsoleTarget { Baseline; BaselineGroup; Launcher; LauncherGroup; PayloadGroup }

///|
priv enum ConsoleEvent { Interrupt; Break }

///|
suberror ControllerInputError { InvalidControllerInput(String) }

///|
fn ConsoleTarget::parse(input : String) -> ConsoleTarget raise ControllerInputError {
  match input {
    "baseline" => Baseline
    "baseline-group" => BaselineGroup
    "launcher" => Launcher
    "launcher-group" => LauncherGroup
    "payload-group" => PayloadGroup
    _ => raise InvalidControllerInput(input)
  }
}

///|
fn ConsoleEvent::parse(input : String) -> ConsoleEvent raise ControllerInputError {
  match input { "CTRL_C" => Interrupt; "CTRL_BREAK" => Break; _ => raise InvalidControllerInput(input) }
}

///|
async fn main {
  assert_eq(@env.get_env_var("OS"), Some("Windows_NT"))
  let args = @env.args()
  assert_eq(args.length(), 6)
  let target = ConsoleTarget::parse(args[1])
  let runner = args[2]
  let wasm = args[3]
  let node = args[4]
  let owner = args[5]
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let pid = start_console(runner, runner.length(), wasm, wasm.length(), node, node.length(), owner, owner.length(),
    match target { Baseline => 1; BaselineGroup => 3; Launcher => 0; LauncherGroup => 2; PayloadGroup => 6 })
  let error = last_error()
  assert_true(pid != 0, msg="CreateProcessW: " + error.to_string())
  defer close_console()
  @stdio.stdout.write("CONTROL_ADDR=" + server.addr.to_string() + "\nCONSOLE_PID=" + pid.to_string() + "\n")
  assert_eq(resume_console(), 0)
  @async.with_task_group(group => {
    let connected = Ref(false)
    let exchange = group.spawn(no_wait=true, () => {
      let (control, _) = server.accept()
      connected.val = true
      defer control.close()
      let kind = ConsoleEvent::parse(control.read_until("\n").unwrap())
      assert_eq(send_event(if kind is Interrupt { 0 } else { 1 }), 0)
      control.write("CTRL_SENT\n")
      // The checker asks about the real Node PID after parent wait completes.
      let input = control.read_until("\n").unwrap()
      guard input.strip_prefix("CHECK_NODE=") is Some(text) else { raise InvalidControllerInput(input) }
      let pid = @string.parse_int(text)
      control.write("NODE_RUNNING=" + process_running(pid).to_string() + "\n")
      control.write("DONE\n")
    })
    let status = @process.wait_pid(pid)
    @stdio.stdout.write("CONSOLE_STATUS=" + status.to_string() + "\n")
    // A live exchange keeps this controller alive through process inspection.
    // A startup failure before the checker connects must still close the pipes.
    if connected.val { exchange.wait() }
  })
}
