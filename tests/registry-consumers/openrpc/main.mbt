///|
fn main raise {
  assert_true(@library.DocumentVersion::parse("1.3.2") is Ok(_))
  println("ok")
}
