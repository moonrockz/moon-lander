///|
fn main raise {
  check_api()
  let host = @library.builder(@core.AppName::parse("registry-stop"), [])
    |> @library.build(_ => ())
  let outcome = @library.run_embedded(host, ctx => {
    let token = ctx.lifetime.stop_token()
    assert_false(ctx.stop_requested())
    assert_false(ctx.lifetime.stop_requested())
    assert_false(token.stop_requested())
    ctx.lifetime.stop_application()
    assert_true(ctx.stop_requested())
    assert_true(ctx.lifetime.stop_requested())
    assert_true(token.stop_requested())
  })
  assert_true(outcome.stop_reason() is Requested)
  assert_eq(outcome.exit_code().to_int(), 0)
  println("ok")
}
