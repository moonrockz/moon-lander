///|
/// Write one line with `console.log`. Node.js writes to a pipe asynchronously
/// on Linux and macOS, so the output scenarios test that the driver lets the
/// pipe drain before the process ends.
// The native version waits on the write, so both versions are async (67).
#warnings("-67")
async fn emit(line : String) -> Unit {
  println(line)
}

///|
/// Start a timer that keeps the Node.js event loop open until the process ends.
extern "js" fn leave_timer_open() -> Unit =
  #|() => { setInterval(() => {}, 1000); }
