///|
struct PythonDescriptor {
  info : @dib.KernelInfo
}

///|
impl @dib.KernelDescriptor for PythonDescriptor with fn kernel_info(self) {
  self.info
}

///|
test "configured codecs accept consumer descriptors and retain independent registries" {
  let python = PythonDescriptor::{ info: @dib.KernelInfo(@dib.KernelName("python"), aliases=[@dib.KernelName("py")]), }
  let base = @dib.Codec::lossless(default=python)
  let codec = base.with_kernel(@dib.KernelInfo(@dib.KernelName("moonbit"), aliases=[@dib.KernelName("mb")]))
  assert_eq(base.registry().resolve("mb"), None)
  assert_eq(codec.registry().resolve("mb"), Some(@dib.KernelName("moonbit")))
  let book = codec.notebook([
    codec.cell(""),
    codec.cell("\r\n42\r", kernel=@dib.KernelName("mb")),
    codec.cell("\n", kernel=@dib.KernelName("markdown")),
  ])
  assert_eq(codec.source_mode(), @dib.Lossless)
  assert_eq(codec.parse(codec.write(book)), book)
  assert_eq(book.cells()[1].kernel(), @dib.KernelName("moonbit"))
  assert_eq(book.cells()[1].source(), "\n42\n")
}

///|
test "configured codec defaults and registration errors stay compatible" {
  let codec = @dib.Codec::new()
  assert_eq(codec.source_mode(), @dib.Normalized)
  assert_eq(codec.parse("#!markdown\n#!fsharp\n42"), @dib.parse("#!markdown\n#!fsharp\n42"))
  try codec.with_kernel(@dib.KernelInfo(@dib.KernelName("other"), aliases=[@dib.KernelName("f#")])) catch {
    @dib.DuplicateKernelName(name) => assert_eq(name, "f#")
    _ => fail("expected typed alias collision")
  } noraise { _ => fail("alias collision was accepted") }
  try codec.cell("", kernel=@dib.KernelName("unknown")) catch {
    @dib.UnknownKernel(_) => ()
    _ => fail("expected unknown kernel")
  } noraise { _ => fail("unknown kernel was accepted") }
}
