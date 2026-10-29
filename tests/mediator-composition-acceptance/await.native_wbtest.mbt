///|
/// A real suspension on the native runtime before the reply is available.
async fn delayed_reply(value : Int) -> Int {
  @aio.sleep(10)
  value
}
