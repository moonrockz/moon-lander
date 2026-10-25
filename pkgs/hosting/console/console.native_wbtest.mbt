///|
extern "C" fn stub_kind_of_event(event : Int) -> Int = "moonlander_console_kind_of_event"

///|
extern "C" fn stub_kind_of_signal(signal : Int) -> Int = "moonlander_console_kind_of_signal"

///|
extern "C" fn stub_exit_code(kind : Int) -> Int = "moonlander_console_exit_code"

///|
test "install succeeds and no signal is recorded before a signal" {
  install()
  assert_true(signal_kind() is None)
}

///|
/// The Windows handler calls this mapping for each console event. A program
/// cannot send `CTRL_CLOSE_EVENT`, and `CTRL_C_EVENT` reaches every process
/// on the console, so this test covers their mapping on every platform.
test "each Windows console event maps to its kind and exit code" {
  let cases : Array[(Int, @hosting.SignalKind, Int)] = [
    (0, Interrupt, 130), // CTRL_C_EVENT
    (1, Quit, 131), // CTRL_BREAK_EVENT
    (2, Terminate, 143), // CTRL_CLOSE_EVENT
  ]
  for case in cases {
    let (event, kind, code) = case
    let mapped = stub_kind_of_event(event)
    assert_eq(kind_of_code(mapped), Some(kind))
    assert_eq(kind.exit_code().to_int(), code)
    // A second event ends the process with this code inside the handler.
    assert_eq(stub_exit_code(mapped), code)
  }
  // CTRL_LOGOFF_EVENT and CTRL_SHUTDOWN_EVENT keep the default behavior.
  assert_eq(stub_kind_of_event(5), 0)
  assert_eq(stub_kind_of_event(6), 0)
}

///|
test "each POSIX signal maps to its kind and exit code" {
  if @async.platform is Windows {
    assert_eq(stub_kind_of_signal(2), 0)
    return
  }
  // The signal numbers that Linux and macOS share.
  let cases : Array[(Int, @hosting.SignalKind, Int)] = [
    (2, Interrupt, 130), // SIGINT
    (15, Terminate, 143), // SIGTERM
    (3, Quit, 131), // SIGQUIT
  ]
  for case in cases {
    let (signal, kind, code) = case
    let mapped = stub_kind_of_signal(signal)
    assert_eq(kind_of_code(mapped), Some(kind))
    assert_eq(stub_exit_code(mapped), code)
  }
  // SIGHUP keeps its default action.
  assert_eq(stub_kind_of_signal(1), 0)
}
