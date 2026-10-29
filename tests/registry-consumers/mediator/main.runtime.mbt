///|
async fn main {
  check_sync()
  let log = []
  let sender = composed((_, request) => {
    @aio.sleep(1)
    log.push("handler")
    request + 1
  }, log)
  assert_eq(sender.send((), 41), 42)
  assert_eq(log, ["before", "handler", "after", "finally"])
  println("ok")
}
