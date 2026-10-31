///|
fn main raise {
  let arguments = @library.Arguments::parse(["", "--", "é🙂", "a\nb"])
  assert_eq(arguments.to_array(), ["", "--", "é🙂", "a\nb"])
  let entry = @library.RelativeFilePath::parse("entry.js")
  let payload = @library.Payload::new([
    @library.PayloadFile::new(entry, b"\x00\xff\n"),
  ], entry)
  assert_eq(payload.files()[0].bytes(), b"\x00\xff\n")
  assert_eq(@library.ProcessStatus::from_bits(0xc000013aU).bits(), 0xc000013aU)
  println("ok")
}
