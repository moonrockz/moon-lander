///|
fn main raise {
  let entry = @library.RelativeFilePath::parse("entry.js")
  let payload = @library.Payload::new([
    @library.PayloadFile::new(entry, b"console.log('ok');"),
  ], entry)
  @launcher_driver.run(Node(@library.NodeLaunch::new(payload, @library.Arguments::empty())))
}
