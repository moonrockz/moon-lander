///|
/// A real suspension on the native runtime before the reply is available.
async fn delayed_reply(value : Int32) -> Int32 {
  @aio.sleep(10)
  value
}
