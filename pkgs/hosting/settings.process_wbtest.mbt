///|
test "omitted native and js settings come from core env" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), []) |> build(_ => ())
  let settings = resolve_settings(host)
  assert_eq(Map::from_iter(settings.variables.iter()), @env.get_env_vars())
  assert_eq(settings.directory, @lander_core.AbsolutePath::parse(@env.current_dir().unwrap()))
}

///|
test "process directory reader parses once and reports absent or invalid paths" {
  assert_eq(process_directory_from(() => Some("/tmp/a\\b")).to_string(), "/tmp/a\\b")
  try { ignore(process_directory_from(() => None)) } catch {
    MissingWorkingDirectory as error => assert_true(error.message().contains("no working directory"))
    error => raise error
  } noraise { _ => fail("expected a missing directory error") }
  try { ignore(process_directory_from(() => Some("relative"))) } catch {
    InvalidWorkingDirectory(error) => assert_true(error is InvalidAbsolutePath(rule=NotAbsolute, ..))
    error => raise error
  } noraise { _ => fail("expected an invalid directory error") }
}
