///|
/// The test program of `mise run check:embedded`. It is the embedder: it runs
/// the host three times in one instance, with `--help`, with `--version` and
/// with no arguments, and writes the exit code after each run. A line after a
/// help or version text proves that the run returned control. The check also
/// reads the imports of its wasm and wasm-gc builds.
fn main {
  for args in [["--help"], ["--version"], []] {
    let host = test_host(args) catch { error => abort("the test host builds: \{error}") }
    let outcome = @hosting.run_embedded(host, _ => println("command"))
    println("code=\{outcome.exit_code().to_int()}")
  }
}

///|
fn test_host(args : Array[String]) -> @hosting.Host[Unit] raise {
  @hosting.builder(@lander_core.AppName::parse("embedded-host"), args)
  |> @hosting_argparse.command(name => @hosting_argparse.Command(name, version="1.2.3"))
  |> @hosting.service("a", start=_ => println("hook=a.start"))
  |> @hosting.build(_ => ())
}
