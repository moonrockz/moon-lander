///|
#external
priv type NodeAdapter

///|
let node : NodeAdapter = node_adapter()

///|
fn stream_fd(stream : @sinks.ConsoleStream) -> Int {
  match stream {
    StandardOutput => 1
    StandardError => 2
  }
}

///|
extern "js" fn NodeAdapter::write_stream(
  self : NodeAdapter,
  fd : Int,
  text : String,
) -> @js_async.Promise[String] =
  #|(adapter, fd, text) => adapter.writeStream(fd, text)

///|
extern "js" fn NodeAdapter::stream_kind(self : NodeAdapter, fd : Int) -> String =
  #|(adapter, fd) => adapter.streamKind(fd)

///|
/// Write `text` to the console stream and wait for the stream callback. It
/// gives the error text when the write fails, else `None`.
async fn write_console(stream : @sinks.ConsoleStream, text : String) -> String? {
  let error = node.write_stream(stream_fd(stream), text).wait() catch {
    error => return Some(failure_text(error))
  }
  if error.is_empty() {
    None
  } else {
    Some(error)
  }
}

///|
/// The terminal kind of the stream from Node.js or Bun: `isTTY` and
/// `hasColors()`. `hasColors()` also reads `NO_COLOR`, `FORCE_COLOR` and `TERM`.
fn console_capability(stream : @sinks.ConsoleStream) -> @sinks.TerminalCapability {
  match node.stream_kind(stream_fd(stream)) {
    "color" => ColorTerminal
    "plain" => PlainTerminal
    "redirected" => Redirected
    _ => Unknown
  }
}
