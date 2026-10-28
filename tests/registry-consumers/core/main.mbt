///|
fn main raise {
  assert_eq(@library.AppName::parse("registry-probe").to_string(), "registry-probe")
  println("ok")
}
