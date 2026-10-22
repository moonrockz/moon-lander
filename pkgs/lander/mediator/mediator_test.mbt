///|
struct Echo(String)

///|
struct Stop(Int32)

///|
suberror AppError {
  Rejected(String)
} derive(Debug)

///|
test "two senders stay separate" {
  let echoes = Ref(0)
  let stops = Ref(0)
  let echo : @mediator.Sender[Unit, Echo, String] = @mediator.sender((_, req) => {
    echoes.val += 1
    let Echo(text) = req
    "Echo: " + text
  })
  let stop : @mediator.Sender[Unit, Stop, Int32] = @mediator.sender((_, req) => {
    stops.val += 1
    let Stop(code) = req
    code
  })
  assert_eq(echo.send((), Echo("Hello")), "Echo: Hello")
  assert_eq(echoes.val, 1)
  assert_eq(stops.val, 0)
  assert_eq(stop.send((), Stop(3)), 3)
  assert_eq(echoes.val, 1)
  assert_eq(stops.val, 1)
  // A request of the wrong type for a sender does not compile. With
  // moonc v0.10.17, `echo.send((), request)` where `request : Stop` fails:
  //   Error: [4014] Expr Type Mismatch
  //     has type : Stop
  //     wanted   : Echo
  // No text-key or untyped send exists to make such a request run.
}

///|
test "a handler error passes out of send unchanged" {
  let echo : @mediator.Sender[Unit, Echo, String] = @mediator.sender((_, req) => {
    let Echo(text) = req
    raise Rejected(text)
  })
  try echo.send((), Echo("Hello")) catch {
    Rejected(text) => assert_eq(text, "Hello")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}
