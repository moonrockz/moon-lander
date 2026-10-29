///|
fn check_sync() -> Unit raise {
  let sender = @library.sender(fn(_ : Unit, request : Int) { request + 1 })
  assert_eq(sender.send((), 41), 42)
}

///|
fn composed(
  handle : async (Unit, Int) -> Int,
  log : Array[String],
) -> @composition.Sender[Unit, Int, Int] {
  @composition.sender(handle)
  .use_(@composition.finally_((_, _) => log.push("finally")))
  .use_(@composition.before((_, _) => log.push("before")))
  .use_(@composition.after((_, _, _) => log.push("after")))
}
