///|
test "omitted wasm and wasm-gc settings are empty and root" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), []) |> build(_ => ())
  let settings = resolve_settings(host)
  assert_eq(Map::from_iter(settings.variables.iter()), Map([]))
  assert_eq(settings.directory, @lander_core.AbsolutePath::root())
}
