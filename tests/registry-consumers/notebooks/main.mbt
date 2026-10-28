///|
fn main raise {
  assert_true(@library.Metadata::empty().is_empty())
  assert_eq(@library.Metadata::empty().to_json(), ({ } : Json))
  println("ok")
}
