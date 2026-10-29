///|
fn main raise {
  check_sync()
  let log = []
  let sender = composed((_, request) => { log.push("handler"); request + 1 }, log)
  let host = @hosting.builder(@core.AppName::parse("public-composition"), [])
    |> @hosting.build(_ => sender)
  let reply : Ref[Int?] = Ref(None)
  let outcome = @hosting.run_embedded(host, ctx => reply.val = Some(ctx.services.send((), 41)))
  assert_eq(outcome.exit_code().to_int(), 0)
  assert_eq(reply.val, Some(42))
  assert_eq(log, ["before", "handler", "after", "finally"])
  println("ok")
}
