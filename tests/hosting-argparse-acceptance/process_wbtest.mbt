///|
/// Test zero is also the child body. Argparse exits before the factory or hook
/// can write a marker. Without the helper variable it returns at once.
async test "helper for argparse process exit and standard error" {
  guard @env.get_env_var("LANDER_ARGPARSE_HELPER") is Some(mode) else { return }
  let argv = match mode {
    "help" => ["--help"]
    "version" => ["--version"]
    _ => ["--no-such-option"]
  }
  let outcome = @hosting.builder(@lander_core.AppName::parse("acme"), argv)
    |> @hosting_argparse.command(name => @argparse.Command(name, version="1.2.3"))
    |> @hosting.service("a", start=_ => println("unexpected hook"))
    |> @hosting.build(_ => println("unexpected factory"))
    |> @hosting.run(_ => println("unexpected command"))
  // A usage error returns to its embedder; help and version exit in argparse.
  assert_eq(outcome.exit_code().to_int(), 2)
}

///|
#cfg(target="native")
fn test_process() -> (String, Array[String]) raise {
  let args = @env.args()
  guard args.length() > 1 && args[1].split(":").next() is Some(file) else {
    fail("unexpected test arguments")
  }
  (args[0], ["\{file}:0-1"])
}

///|
#cfg(target="native")
async test "help and version exit with 0 before services and usage errors write argparse text to stderr" {
  let (exe, args) = test_process()
  for (mode, text) in [("help", "Usage: acme"), ("version", "1.2.3"), ("unknown", "--no-such-option")] {
    let (code, out, err) = @async.with_timeout(10000, () => @process.collect_output(exe, args,
      extra_env=Map::from_array([("LANDER_ARGPARSE_HELPER", mode)])))
    assert_eq(code, 0, msg=out.text() + err.text())
    let output = if mode == "unknown" { err.text() } else { out.text() }
    assert_true(output.contains(text), msg=output)
    if mode == "unknown" { assert_true(output.contains("acme: error:"), msg=output) }
    else { assert_eq(err.text(), "") }
    assert_false(out.text().contains("unexpected"), msg=out.text())
    assert_false(err.text().contains("unexpected factory"), msg=err.text())
  }
}
