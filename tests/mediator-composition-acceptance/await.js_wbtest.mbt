///|
/// A real JavaScript Promise resolved on a later event-loop turn.
extern "js" fn reply_promise(value : Int) -> @js_async.Promise[Int] =
  #|(value) => new Promise(resolve => setTimeout(() => resolve(value), 10))

///|
async fn delayed_reply(value : Int) -> Int {
  reply_promise(value).wait()
}
