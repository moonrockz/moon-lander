///|
/// A real JavaScript Promise resolved on a later event-loop turn.
extern "js" fn reply_promise(value : Int32) -> @js_async.Promise[Int32] =
  #|(value) => new Promise(resolve => setTimeout(() => resolve(value), 10))

///|
async fn delayed_reply(value : Int32) -> Int32 {
  reply_promise(value).wait()
}
