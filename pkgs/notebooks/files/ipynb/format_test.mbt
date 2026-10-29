///|
test "DIB and Jupyter represent the same text tree with generic VFS metadata" {
  let dib_format = @tree_dib.Format::new(default=@source_dib.KernelInfo(@source_dib.KernelName("moonbit")))
    .with_kernel(@source_dib.KernelInfo(@source_dib.KernelName("python")))
  let dib = "#!tree\n#!directory fixtures/empty\n#!moonbit\n#!file src/main.mbt\n\nlet answer = 42\n\n#!python\n#!file tools/build.py\nprint(42)\n#!markdown\n#!file README.md\n# Example\n#!text\n#!file empty.txt\n"
  let tree = dib_format.read(dib)
  let format = @tree_ipynb.Format::new()
  let notebook = format.to_notebook(tree)
  assert_eq(notebook.nbformat_minor(), 5)
  assert_eq(notebook.metadata().get_json("vfs"), Some({ "version": 1, "directories": ["fixtures/empty"], }))
  assert_eq(notebook.cells()[0].metadata().get_json("vfs"), Some({ "path": "src/main.mbt", "kernel": "moonbit", }))
  assert_eq(notebook.cells()[0].source(), Some("\nlet answer = 42\n"))
  assert_eq(notebook.cells()[2].cell_type(), "markdown")
  assert_eq(notebook.cells()[3].cell_type(), "raw")
  assert_eq(format.read(format.write(tree)), tree)
  assert_eq(dib_format.read(dib_format.write(format.read(format.write(tree)))), tree)
  let empty = @files.FileTree::new([])
  assert_eq(format.read(format.write(empty)), empty)
}

///|
test "Jupyter extraction keeps original metadata notes outputs and attachments unchanged" {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{"title":"Original"},"cells":[
    #|{"id":"note","cell_type":"markdown","metadata":{},"source":"Notes","attachments":{"image":{"image/png":"AAAA"}}},
    #|{"id":"file","cell_type":"code","metadata":{"vfs":{"path":"run.py","kernel":"python"},"other":"keep"},"source":["#!file literal\n","print(42)\n"],"execution_count":1,"outputs":[{"output_type":"stream","name":"stdout","text":"not file content"}]}
    #|]}
  let notebook = @nbformat.parse(source)
  let original = notebook.to_string()
  let tree = @tree_ipynb.Format::new().from_notebook(notebook)
  assert_eq(tree.files().length(), 1)
  assert_eq(tree.files()[0].source(), "#!file literal\nprint(42)\n")
  assert_eq(notebook.to_string(), original)
  assert_eq(notebook.cells()[1].outputs().length(), 1)
}

///|
test "Jupyter VFS rejects malformed versions declarations and conflicts" {
  let format = @tree_ipynb.Format::new()
  let headers : Array[Json] = [
    { "vfs": Json::null(), }, { "vfs": [], },
    { "vfs": { "directories": [], }, },
    { "vfs": { "version": 2, }, },
    { "vfs": { "version": "1", }, },
    { "vfs": { "version": 1, "directories": "bad", }, },
    { "vfs": { "version": 1, "directories": [Json::null()], }, },
  ]
  for metadata in headers {
    let notebook = @nbformat.Notebook::Notebook([], metadata=@notebooks.Metadata(metadata))
    try format.from_notebook(notebook) catch {
      @tree_ipynb.InvalidMetadata(..) => ()
      _ => fail("expected typed VFS shape failure")
    } noraise { _ => fail("accepted malformed VFS header") }
  }
  let declarations : Array[Json] = [Json::null(), [], {}, { "path": "a", }, { "path": "a", "kernel": Json::null(), }, { "path": 1, "kernel": "python", }]
  for vfs in declarations {
    let cell = @nbformat.Cell::Cell(@nbformat.Raw(source="", attachments=None), id=Some(@nbformat.CellId("x")), metadata=@notebooks.Metadata({ "vfs": vfs, }))
    let notebook = @nbformat.Notebook::Notebook([cell])
    try format.from_notebook(notebook) catch {
      @tree_ipynb.InvalidMetadata(..) => ()
      _ => fail("expected typed file metadata failure")
    } noraise { _ => fail("accepted malformed file metadata") }
  }
  let cell = @nbformat.Cell::Cell(@nbformat.Raw(source="", attachments=None), id=Some(@nbformat.CellId("x")), metadata=@notebooks.Metadata({ "vfs": { "path": "a", "kernel": "text", }, }))
  let other = @nbformat.Cell::Cell(@nbformat.Raw(source="", attachments=None), id=Some(@nbformat.CellId("y")), metadata=cell.metadata())
  try format.from_notebook(@nbformat.Notebook::Notebook([cell, other])) catch {
    @files.DuplicatePath(_) => ()
    _ => fail("expected duplicate path")
  } noraise { _ => fail("accepted duplicate file cells") }
}

///|
test "Jupyter marked unknown cells are refused and selector-shaped content is valid" {
  let format = @tree_ipynb.Format::new()
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"id":"x","cell_type":"future","metadata":{"vfs":{"path":"x","kernel":"text"}}}]}
  let notebook = @nbformat.parse(source)
  try format.from_notebook(notebook) catch {
    @tree_ipynb.UnsupportedCell(index~, cell_type~) => {
      assert_eq(index, 0)
      assert_eq(cell_type, "future")
    }
    _ => fail("expected marked cell source refusal")
  } noraise { _ => fail("accepted unknown source payload") }
  let tree = @files.FileTree::new([@files.TextFile::new(@files.TreePath::parse("nested.dib"), "#!fsharp\n42\n", kernel=@source_dib.KernelName("text"))])
  assert_eq(format.read(format.write(tree)), tree)
}
