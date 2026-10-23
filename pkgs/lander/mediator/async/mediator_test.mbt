///|
struct Echo(String)

///|
suberror EchoError {
  Closed(String)
} derive(Debug)

///|
async test "send an echo through a handler that waits" {
  let calls = Ref(0)
  let echo : @mediator_async.Sender[Unit, Echo, String] = @mediator_async.sender((
    _,
    req,
  ) => {
    @async.sleep(10)
    calls.val += 1
    let Echo(text) = req
    "Echo: " + text
  })
  assert_eq(echo.send((), Echo("Hello")), "Echo: Hello")
  assert_eq(calls.val, 1)
}

///|
/// A request of another type does not compile. With
/// `echo : Sender[Unit, Echo, String]` and `stop : Stop`, where `Stop` is a
/// record, `echo.send((), stop)` gives (moonc v0.10.17):
///
///   Error: [4014] Expr Type Mismatch
///       has type : Stop
///       wanted   : Echo
async test "a handler error passes out of send unchanged" {
  let echo : @mediator_async.Sender[Unit, Echo, String] = @mediator_async.sender((
    _,
    req,
  ) => {
    @async.sleep(10)
    let Echo(text) = req
    raise Closed(text)
  })
  try echo.send((), Echo("Hello")) catch {
    Closed(text) => assert_eq(text, "Hello")
    other => fail("send raised another error: \{other}")
  } noraise {
    reply => fail("send gave a reply: \{reply}")
  }
}
