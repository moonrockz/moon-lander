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
  verify_file_trees()
  println("ok")
}

///|
struct Python {
  info : @dib.KernelInfo
}

///|
impl @dib.KernelDescriptor for Python with fn kernel_info(self) { self.info }

///|
fn verify_file_trees() -> Unit raise {
  let python = Python::{ info: @dib.KernelInfo(@dib.KernelName("python"), aliases=[@dib.KernelName("py")]), }
  let codec = @dib.Codec::lossless(default=python)
  let empty = codec.notebook([codec.cell(""), codec.cell("\n42\n")])
  assert_eq(codec.parse(codec.write(empty)), empty)
  let format = @tree_dib.Format::new(default=python)
    .with_kernel(@dib.KernelInfo(@dib.KernelName("moonbit")))
  let tree = format.read("#!tree\n#!directory fixtures/empty\n#!py\n#!file run.py\n\nprint(42)\n\n#!moonbit\n#!file main.mbt\nlet answer = 42\n#!text\n#!file empty.txt\n")
  assert_eq(tree.files().length(), 3)
  assert_eq(tree.files()[0].source(), "\nprint(42)\n")
  assert_eq(tree.files()[0].kernel(), @dib.KernelName("python"))
  assert_eq(tree.files()[2].source(), "")
  assert_eq(tree.explicit_directories(), [@files.TreePath::parse("fixtures/empty")])
  let jupyter = @tree_ipynb.Format::new()
  let notebook = jupyter.to_notebook(tree)
  assert_eq(notebook.cells()[0].metadata().get_json("vfs"), Some({ "path": "run.py", "kernel": "python", }))
  assert_eq(jupyter.read(jupyter.write(tree)), tree)
  assert_eq(format.read(format.write(jupyter.from_notebook(notebook))), tree)
  let converted_tree = @files.convert_tree(format.write(tree), source=format, target=jupyter)
  assert_eq(jupyter.read(converted_tree), tree)
  let converter = @conversion.Converter::new(policy=@conversion.SourceOnly)
  let converted = converter.to_jupyter(empty)
  assert_eq(converter.to_dib(converted.notebook()).notebook().cells(), empty.cells())
}
