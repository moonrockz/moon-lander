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
  let capture = node_fixture().capture_stderr("stderr: ")
  defer ignore(capture.finish())
  let host : Host[Unit] = builder(@lander_core.AppName::parse("stderr"), [])
    |> build(_ => ())
  let result = run(host, _ => raise UsageError("invalid option"))
  @expect.expect(result.exit_code().to_int()).to_equal(2)
  @expect.expect(capture.finish()).to_equal("stderr: invalid option\n")
}
