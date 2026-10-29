# Virtual text file trees

`moonrockz/notebooks/files` models immutable text files and explicit directories
under one virtual root. It performs no I/O. Text uses LF line endings, including
leading and trailing empty lines. File order and explicit directory order are
retained. Parent directories are inferred; repeated directory declarations are
idempotent. Duplicate file paths and file/directory conflicts raise `TreeError`.

```mbt check
///|
test "example: construct a virtual text tree" {
  let path = @files.TreePath::parse("src/main.mbt")
  let file = @files.TextFile::new(
    path, "let answer = 42\n", kernel=@dib.KernelName("moonbit"),
  )
  let tree = @files.FileTree::new([
    file,
  ], directories=[@files.TreePath::parse("fixtures/empty")])
  assert_eq(tree.file(path), Some(file))
  assert_true(tree.directories().contains(@files.TreePath::parse("src")))
}
```

Paths must be nonempty and relative, with `/` separators. Empty, `.` and `..`
segments, absolute or drive-qualified paths, backslashes, NUL and line breaks
raise a typed error. This is a virtual naming contract, not a promise that every
name can be materialized on every host filesystem.

Use [DIB file trees](dib/README.mbt.md) or [Jupyter VFS metadata](ipynb/README.mbt.md)
to read and write the same model. Kernel names describe content. They do not
install a runtime or execute files. Prefer canonical names when constructing
files for DIB export, or use its format's `file` method to resolve aliases.

These are explicit tree projections. Reading does not modify the source
notebook. Writing a tree creates a fresh document and does not reproduce
unmarked notes, unrelated metadata, outputs, attachments or original cell IDs.
Keep the notebook object for full-document editing. Binary files, symlinks,
filesystem writes and overlay policies are outside this API.

## Convert tree formats

Both adapters implement the open `TreeFormat` trait.
`convert_tree(text, source=from_format, target=to_format)` reads the explicit tree
projection and writes its target representation. For whole source notebooks,
use the separate [source converter](../conversion/README.mbt.md), which reports
format-specific state that cannot be retained.
