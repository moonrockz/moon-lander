///|
struct Ping(String)

///|
test "send a ping gives the handler reply and runs the handler one time" {
  let calls = Ref(0)
  let ping : Sender[Unit, Ping, String] = sender((_, req) => {
    calls.val += 1
    let Ping(text) = req
    "Pong: " + text
  })
  assert_eq(ping.send((), Ping("Hello")), "Pong: Hello")
  assert_eq(calls.val, 1)
}
