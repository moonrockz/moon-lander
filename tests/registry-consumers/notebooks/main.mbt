///|
fn main raise {
  assert_true(@library.Metadata::empty().is_empty())
  assert_eq(@library.Metadata::empty().to_json(), ({ } : Json))
  let source_mode = @dib.SourceMode::Lossless
  let registry = @dib.KernelRegistry(
    [@dib.KernelInfo(@dib.KernelName("scheme"))],
    default_kernel=@dib.KernelName("scheme"),
  )
  let original = @dib.Notebook::Notebook([
    @dib.Cell::Cell("", kernel=@dib.KernelName("markdown"), source_mode~),
    @dib.Cell::Cell("\n42\n", kernel=@dib.KernelName("scheme"), source_mode~),
    @dib.Cell::Cell("", kernel=@dib.KernelName("scheme"), source_mode~),
  ], registry~)
  let parsed = @dib.parse(original.to_string(source_mode~), registry~, source_mode~)
  assert_eq(parsed, original)
  assert_eq(parsed.cells().length(), 3)
  println("ok")
}
