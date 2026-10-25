///|
#external
priv type NodeAdapter

///|
extern "js" fn NodeAdapter::write_stderr(
  self : NodeAdapter,
  text : String,
) -> @js_async.Promise[Unit] =
  #|(adapter, text) => adapter.writeStderr(text)

///|
let node_reports : NodeAdapter = node_adapter()

///|
async fn write_report_line(text : String) -> Unit {
  node_reports.write_stderr(text + "\n").wait()
}
