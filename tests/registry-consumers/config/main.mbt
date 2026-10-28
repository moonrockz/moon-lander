///|
fn main raise {
  let config = @library.build([@library.in_memory_pairs([("probe", @library.string("ready"))])])
  assert_eq(@library.get_text(config, "probe"), "ready")
  println("ok")
}
