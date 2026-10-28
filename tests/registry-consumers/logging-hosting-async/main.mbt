///|
fn main raise {
  assert_true(@library.SessionSettings::standard().console() is Some(_))
  println("ok")
}
