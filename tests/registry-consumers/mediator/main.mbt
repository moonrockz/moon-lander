///|
fn main raise {
  let sender = @library.sender(fn(_ : Unit, request : Int) { request + 1 })
  assert_eq(sender.send((), 41), 42)
  println("ok")
}
