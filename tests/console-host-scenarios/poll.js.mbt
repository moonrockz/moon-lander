///|
/// The parent stays responsive while this real foreign callback never yields.
extern "js" fn poll_foreign(read : () -> Bool, stopped : () -> Unit) -> @js_async.Promise[Unit] =
  #|(read, stopped) => new Promise((resolve, reject) => setTimeout(() => {
  #|  try {
  #|    console.log("ready");
  #|    while (!read()) {}
  #|    stopped();
  #|    resolve();
  #|  } catch (error) { reject(error); }
  #|}, 0))

///|
async fn poll_stop(ctx : @hosting.Context[Unit], stopped : () -> Unit) -> Unit {
  poll_foreign(() => ctx.stop_requested(), stopped).wait()
}
