///|
// The async stdio handles permit one writer at a time. Every session of the
// process and the direct diagnostic writer share these locks.
let stderr_lock : @async.Mutex = @async.Mutex::Mutex()

///|
let stdout_lock : @async.Mutex = @async.Mutex::Mutex()

///|
/// Write `text` to the console stream. It gives the error text when the write
/// fails, else `None`.
async fn write_console(stream : @sinks.ConsoleStream, text : String) -> String? {
  let lock = match stream {
    StandardError => stderr_lock
    StandardOutput => stdout_lock
  }
  lock.acquire()
  defer lock.release()
  try {
    match stream {
      StandardError => @stdio.stderr.write(text)
      StandardOutput => @stdio.stdout.write(text)
    }
    None
  } catch {
    error => Some(failure_text(error))
  }
}

///|
/// The pinned `moonbitlang/async` gives no public terminal check, and this
/// package adds no C stub for it, so `Auto` colors stay off on native. Use
/// `Always` to force the Literate theme.
fn console_capability(_stream : @sinks.ConsoleStream) -> @sinks.TerminalCapability {
  Unknown
}
