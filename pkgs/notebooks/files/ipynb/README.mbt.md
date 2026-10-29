# Jupyter virtual file trees

The version-1 VFS convention stores transport information in `metadata.vfs`.
It is an application convention, not an official Jupyter metadata standard.
No directive is inserted into file content.

Notebook metadata declares the version and optional explicit directories:

```json
{"vfs":{"version":1,"directories":["fixtures/empty"]}}
```

Each selected cell has metadata like this:

```json
{"vfs":{"path":"src/main.mbt","kernel":"moonbit"}}
```

Cell `source` is the whole file content. The notebook-level header may be absent
when cells independently declare files. A present header must be an object with
version 1; directories, when present, must be an array of relative path strings.
A cell-level declaration requires both path and kernel strings. Malformed shapes
raise `MappingError`; invalid paths or conflicts retain typed tree errors.

```mbt check
///|
test "example: Jupyter file metadata has clean cell source" {
  let format = @tree_ipynb.Format::new()
  let tree = @files.FileTree::new([
    @files.TextFile::new(
      @files.TreePath::parse("src/main.mbt"), "let answer = 42\n",
      kernel=@source_dib.KernelName("moonbit"),
    ),
  ], directories=[@files.TreePath::parse("fixtures/empty")])
  let notebook = format.to_notebook(tree)
  assert_eq(notebook.cells()[0].source(), Some("let answer = 42\n"))
  assert_eq(
    notebook.cells()[0].metadata().get_json("vfs"),
    Some({ "path": "src/main.mbt", "kernel": "moonbit", }),
  )
  assert_eq(format.read(format.write(tree)), tree)
}
```

Reading selects marked source cells and ignores notes, outputs and attachments.
It leaves the original immutable notebook intact. A marked unknown cell without
a recognized source payload is refused. Writing creates a fresh valid v4.5
notebook with stable `file-<index>` IDs, no outputs and null execution counts.
The `text` kernel writes as raw, `markdown` as Markdown and other kernels as code.

Per-file kernel labels describe content. They do not configure a Jupyter runtime
for multiple languages. Notebook execution remains the application's concern.
Text is LF-normalized in the shared tree, and export is not byte reproduction.

Jupyter permits custom metadata in a distinct namespace. The format contract is
described in the [upstream notebook documentation](https://nbformat.readthedocs.io/en/latest/format_description.html#metadata).
