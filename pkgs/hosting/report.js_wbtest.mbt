///|
#external
priv type NodeFixture

///|
#external
priv type StderrCapture

///|
extern "js" fn NodeFixture::capture_stderr(self : NodeFixture, prefix : String) -> StderrCapture =
  #|(fixture, prefix) => fixture.captureStderr(prefix)

///|
extern "js" fn StderrCapture::finish(self : StderrCapture) -> String =
  #|capture => capture.finish()

///|
async test "default report reaches standard error and waits for write completion" {
  for timeout in [false, true] {
    let capture = node_fixture().capture_stderr("stderr: ")
    defer ignore(capture.finish())
    let host : Host[Unit] = builder(@lander_core.AppName::parse("stderr"), [])
      |> shutdown_timeout(@lander_core.TimeLimit::millis(20))
      |> service("slow", stop=_ => { if timeout { @async.sleep(10000) } })
      |> build(_ => ())
    let result = run(host, _ => { if !timeout { raise UsageError("invalid option") } })
    @expect.expect(result.exit_code().to_int()).to_equal(if timeout { 1 } else { 2 })
    @expect.expect(capture.finish()).to_equal(if timeout {
      "stderr: Shutdown timed out after 20ms\n"
    } else { "stderr: invalid option\n" })
  }
}
