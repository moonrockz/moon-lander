///|
test "omitted native and js settings come from core env" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), []) |> build(_ => ())
  let settings = resolve_settings(host)
  assert_eq(settings.variables, @env.get_env_vars())
  assert_eq(settings.directory, @lander_core.AbsolutePath::parse(@env.current_dir().unwrap_or("/")))
}
