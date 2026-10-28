///|
fn main raise {
  let memory = @library.MemoryLogger::new()
  (memory : &@library.Logger).info("Registry {Count}", [1])
  assert_eq(memory.events()[0].message(), "Registry 1")
  println("ok")
}
