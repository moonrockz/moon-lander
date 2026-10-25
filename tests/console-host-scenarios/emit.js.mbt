///|
/// Write one line with `console.log`. Node.js writes to a pipe asynchronously
/// on Linux and macOS, so the output scenarios test that the driver lets the
/// pipe drain before the process ends.
// The native version waits on the write, so both versions are async (67).
#warnings("-67")
async fn emit(line : String) -> Unit {
  println(line)
}
