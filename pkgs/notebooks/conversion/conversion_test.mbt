///|
test "source conversion preserves empty custom-kernel cells and metadata" {
  let codec = @dib.Codec::lossless(default=@dib.KernelInfo(@dib.KernelName("moonbit")))
    .with_kernel(@dib.KernelInfo(@dib.KernelName("python"), aliases=[@dib.KernelName("py")]))
  let book = codec.notebook([
    codec.cell(""), codec.cell("\nprint(42)\n", kernel=@dib.KernelName("py")),
    codec.cell("", kernel=@dib.KernelName("markdown")),
  ], metadata=@notebooks.Metadata({ "title": "Example", }))
  let converter = @conversion.Converter::new(policy=@conversion.SourceOnly)
  let jupyter = converter.to_jupyter(book)
  assert_true(jupyter.losses().is_empty())
  assert_eq(jupyter.notebook().cells().length(), 3)
  assert_eq(jupyter.notebook().cells()[1].metadata().get_json("polyglot_notebook"), Some({ "kernelName": "python", }))
  let restored = converter.to_dib(@nbformat.parse(jupyter.text()))
  assert_eq(restored.notebook().cells(), book.cells())
  assert_eq(restored.notebook().metadata().get_json("title"), Some("Example"))
  assert_eq(restored.losses(), [@conversion.CellIdentity(cell=0), @conversion.CellIdentity(cell=1), @conversion.CellIdentity(cell=2)])
  assert_eq(@dib.parse(restored.text(), source_mode=@dib.Lossless).cells(), book.cells())
  try @conversion.Converter::new().to_dib(jupyter.notebook()) catch {
    @conversion.Lossy(losses) => assert_eq(losses.length(), 3)
    _ => fail("expected explicit cell identity losses")
  } noraise { _ => fail("strict conversion discarded IDs") }
}

///|
test "strict source conversion accepts unexecuted source with no unsupported state" {
  let notebook = @nbformat.Notebook::Notebook([
    @nbformat.Cell::Cell(@nbformat.Code(source="42", execution_count=None, outputs=[])),
    @nbformat.Cell::Cell(@nbformat.Markdown(source="", attachments=None)),
    @nbformat.Cell::Cell(@nbformat.Raw(source="\ntext\n", attachments=None)),
  ], minor=4)
  let converter = @conversion.Converter::new()
  let dib = converter.to_dib(notebook)
  assert_true(dib.losses().is_empty())
  let jupyter = converter.to_jupyter(dib.notebook())
  assert_eq(jupyter.notebook().cells().map(cell => cell.source()), notebook.cells().map(cell => cell.source()))
  assert_eq(jupyter.notebook().cells()[2].cell_type(), "raw")
}

///|
test "conversion reports execution attachments metadata and extension losses" {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"custom_root":42,"metadata":{},"cells":[
    #|{"id":"code","cell_type":"code","custom_cell":true,"metadata":{"tags":["keep"]},"source":"42","execution_count":0,"outputs":[{"output_type":"stream","name":"stdout","text":"output"}]},
    #|{"id":"md","cell_type":"markdown","metadata":{},"source":"# Title","attachments":{"x":{"text/plain":"attachment"}}}
    #|]}
  let notebook = @nbformat.parse(source)
  let converter = @conversion.Converter::new(policy=@conversion.SourceOnly)
  let result = converter.to_dib(notebook)
  for loss in [
    @conversion.NotebookExtensions, @conversion.CellIdentity(cell=0),
    @conversion.CellMetadata(cell=0), @conversion.CellExtensions(cell=0),
    @conversion.ExecutionCount(cell=0), @conversion.Outputs(cell=0),
    @conversion.CellIdentity(cell=1), @conversion.Attachments(cell=1),
  ] { assert_true(result.losses().contains(loss)) }
  assert_eq(result.notebook().cells()[0].source(), "42")
  assert_eq(notebook.cells()[0].outputs().length(), 1)
  try @conversion.Converter::new().to_dib(notebook) catch {
    @conversion.Lossy(losses) => assert_eq(losses, result.losses())
    _ => fail("expected strict loss report")
  } noraise { _ => fail("strict conversion dropped execution state") }
}

///|
test "conversion resolves Jupyter kernel metadata and refuses unknown source framing" {
  let source =
    #|{"nbformat":4,"nbformat_minor":4,"metadata":{"kernelspec":{"name":"python3","display_name":"Python"},"language_info":{"name":"python"}},"cells":[{"cell_type":"code","metadata":{},"source":"print(42)","execution_count":null,"outputs":[]}]}
  let notebook = @nbformat.parse(source)
  let converter = @conversion.Converter::new().with_kernel(@dib.KernelInfo(@dib.KernelName("python")))
  assert_eq(converter.to_dib(notebook).notebook().cells()[0].kernel(), @dib.KernelName("python"))
  let malformed = @nbformat.Notebook::Notebook([
    @nbformat.Cell::Cell(@nbformat.Code(source="", execution_count=None, outputs=[]), metadata=@notebooks.Metadata({ "polyglot_notebook": { "kernelName": 1, }, })),
  ], minor=4)
  try converter.to_dib(malformed) catch {
    @conversion.InvalidKernelMetadata(_) => ()
    _ => fail("expected kernel metadata error")
  } noraise { _ => fail("accepted malformed kernel name") }
  let split = @nbformat.Notebook::Notebook([
    @nbformat.Cell::Cell(@nbformat.Code(source="#!fsharp\n42", execution_count=None, outputs=[])),
  ], minor=4)
  try converter.to_dib(split) catch {
    @dib.UnrepresentableSource(..) => ()
    _ => fail("expected source boundary refusal")
  } noraise { _ => fail("accepted silently split source") }
}

///|
test "tree format trait converts VFS without transport directives in Jupyter source" {
  let dib = @tree_dib.Format::new()
  let ipynb = @tree_ipynb.Format::new()
  let source = "#!tree\n#!directory fixtures/empty\n#!text\n#!file empty.txt\n#!markdown\n#!file README.md\n# Example\n"
  let converted = @files.convert_tree(source, source=dib, target=ipynb)
  assert_eq(@nbformat.parse(converted).cells()[0].source(), Some(""))
  let restored = @files.convert_tree(converted, source=ipynb, target=dib)
  assert_eq(dib.read(restored), dib.read(source))
}

///|
test "conversion reports replaced registrations and refuses unknown cell payloads" {
  let codec = @dib.Codec::lossless()
  let book = codec.notebook([codec.cell("42")], metadata=@notebooks.Metadata({
    "polyglot_notebook": { "label": "keep", "kernelInfo": { "items": [], }, },
  }))
  try @conversion.Converter::new().to_jupyter(book) catch {
    @conversion.Lossy(losses) => assert_eq(losses, [@conversion.NotebookKernelMetadata])
    _ => fail("expected replaced registration report")
  } noraise { _ => fail("silently replaced metadata") }
  let result = @conversion.Converter::new(policy=@conversion.SourceOnly).to_jupyter(book)
  assert_eq(result.losses(), [@conversion.NotebookKernelMetadata])
  guard result.notebook().metadata().get_json("polyglot_notebook") is Some(Object(fields)) else { fail("missing kernel metadata") }
  assert_eq(fields.get("label"), Some("keep"))
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"id":"x","cell_type":"future","metadata":{},"source":"opaque"}]}
  try @conversion.Converter::new(policy=@conversion.SourceOnly).to_dib(@nbformat.parse(source)) catch {
    @conversion.UnsupportedCell(cell~, cell_type~) => {
      assert_eq(cell, 0)
      assert_eq(cell_type, "future")
    }
    _ => fail("expected unsupported cell refusal")
  } noraise { _ => fail("invented a source conversion for an unknown cell") }
}
