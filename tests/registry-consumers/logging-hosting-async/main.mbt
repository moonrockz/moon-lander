///|
fn main raise {
  assert_true(@library.SessionSettings::standard().console() is Some(_))
  // Compile the public policy seam with caller-provided typed paths and stems.
  let configure = (directory, stem) => @library.FileSink::new(directory, stem, format=JsonLines, json_properties=NamedObject)
  ignore(configure)
  ignore(@library.FileSink::json_properties)
  println("ok")
}
