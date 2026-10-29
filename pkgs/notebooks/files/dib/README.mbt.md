# DIB file trees

Configure a format once. `KernelInfo` and consumer-defined `KernelDescriptor`
implementations supply kernel names and aliases. The format selects lossless
source handling and adds reserved `tree` and `text` kernels. With no custom
default it starts with the standard DIB registry; a supplied descriptor starts
a custom registry with Markdown available. Registration returns a new format.

```mbt check
///|
test "example: DIB file tree with a custom kernel" {
  let format = @tree_dib.Format::new(
    default=@source_dib.KernelInfo(@source_dib.KernelName("moonbit")),
  ).with_kernel(@source_dib.KernelInfo(
    @source_dib.KernelName("python"), aliases=[@source_dib.KernelName("py")],
  ))
  let source =
    #|#!tree
    #|#!directory fixtures/empty
    #|#!moonbit
    #|#!file src/main.mbt
    #|let answer = 42
    #|#!py
    #|#!file tools/build.py
    #|print(42)
    #|#!text
    #|#!file empty.txt
  let tree = format.read(source)
  assert_eq(tree.files().length(), 3)
  assert_eq(tree.files()[2].source(), "")
  assert_eq(format.read(format.write(tree)), tree)
  let file = format.file(
    @files.TreePath::parse("other.py"), "print(1)\n",
    kernel=@source_dib.KernelName("py"),
  )
  assert_eq(file.kernel(), @source_dib.KernelName("python"))
}
```

A file cell starts with `#!file path`. Only that first line is transport; all
remaining lines are content, including later directives. Unmarked cells are
outside the projection. A `#!tree` manifest contains `#!directory path` lines;
empty manifest lines are allowed. Directories containing files are inferred.

Paths accept plain text or a JSON string. Writing always emits JSON strings,
so spaces and quotes are unambiguous. For example, `#!file "some dir/a.txt"`.
Empty files and explicit empty directories are retained.

Use canonical kernel names for programmatically constructed trees. Export
rejects aliases that would silently change identity, unknown kernels and the
reserved manifest kernel as file content. `format.file` resolves a name or alias
to the canonical name during construction.

DIB cannot represent a literal registered selector at column zero inside a
single cell. Writing retains `UnrepresentableSource` for such files. It does
not invent an escape or silently split the content. Jupyter can represent that
source through its VFS metadata mapping.
