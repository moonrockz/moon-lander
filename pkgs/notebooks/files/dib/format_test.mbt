///|
test "DIB virtual tree retains custom kernels source boundaries and empty entries" {
  let format = @tree_dib.Format::new(default=@source_dib.KernelInfo(@source_dib.KernelName("moonbit")))
    .with_kernel(@source_dib.KernelInfo(@source_dib.KernelName("python"), aliases=[@source_dib.KernelName("py")]))
  let document = "#!tree\n#!directory fixtures/empty\n#!moonbit\n#!file src/main.mbt\n\nlet answer = 42\n\n#!py\n#!file tools/build.py\nprint(42)\n#!markdown\n#!file README.md\n# Example\n#!text\n#!file assets/empty.txt\n"
  let tree = format.read(document)
  assert_eq(tree.files().length(), 4)
  assert_eq(tree.files()[0].source(), "\nlet answer = 42\n")
  assert_eq(tree.files()[1].kernel(), @source_dib.KernelName("python"))
  assert_eq(tree.files()[3].source(), "")
  assert_eq(tree.explicit_directories(), [@files.TreePath::parse("fixtures/empty")])
  assert_eq(format.read(format.write(tree)), tree)
  assert_eq(format.read(format.write(@files.FileTree::new([]))), @files.FileTree::new([]))
}

///|
test "DIB file declarations only consume the first source line and quote paths" {
  let format = @tree_dib.Format::new()
  let path = @files.TreePath::parse("space dir/a\"b.txt")
  let file = @files.TextFile::new(path, "#!file literal\n#!meta\n{}\n", kernel=@source_dib.KernelName("text"))
  let tree = @files.FileTree::new([file])
  assert_eq(format.read(format.write(tree)), tree)
  let note = format.read("#!markdown\n# Notes\n#!file later-is-source\n")
  assert_true(note.files().is_empty())
  for text in ["#!text\n#!file\n", "#!text\n#!file \"bad\n", "#!tree\nnot-a-directory\n"] {
    try format.read(text) catch {
      @tree_dib.InvalidDeclaration(..) => ()
      _ => fail("expected typed malformed declaration")
    } noraise { _ => fail("accepted malformed declaration") }
  }
}

///|
test "DIB tree export retains selector refusal and rejects alias ambiguity" {
  let format = @tree_dib.Format::new()
  let path = @files.TreePath::parse("example.txt")
  let tree = @files.FileTree::new([@files.TextFile::new(path, "#!fsharp", kernel=@source_dib.KernelName("text"))])
  try format.write(tree) catch {
    @source_dib.UnrepresentableSource(..) => ()
    _ => fail("expected selector collision")
  } noraise { _ => fail("accepted source split") }
  let aliased_tree = @files.FileTree::new([@files.TextFile::new(path, "", kernel=@source_dib.KernelName("f#"))])
  try format.write(aliased_tree) catch {
    @tree_dib.NonCanonicalKernel(..) => ()
    _ => fail("expected canonical kernel requirement")
  } noraise { _ => fail("silently changed kernel identity") }
}

///|
test "plain text defaults resolve aliases and export rejects reserved or unknown kernels" {
  let format = @tree_dib.Format::new(default=@source_dib.KernelInfo(
    @source_dib.KernelName("text"), aliases=[@source_dib.KernelName("plain")],
  ))
  let path = @files.TreePath::parse("a.txt")
  let file = format.file(path, "\n", kernel=@source_dib.KernelName("plain"))
  let tree = @files.FileTree::new([file])
  assert_eq(file.kernel(), @source_dib.KernelName("text"))
  assert_eq(format.read(format.write(tree)), tree)
  let reserved = @files.FileTree::new([@files.TextFile::new(path, "", kernel=@source_dib.KernelName("tree"))])
  try format.write(reserved) catch {
    @tree_dib.ReservedKernel(name) => assert_eq(name, @source_dib.KernelName("tree"))
    _ => fail("expected reserved kernel failure")
  } noraise { _ => fail("accepted manifest kernel as file") }
  let unknown = @files.FileTree::new([@files.TextFile::new(path, "", kernel=@source_dib.KernelName("unknown"))])
  try format.write(unknown) catch {
    @source_dib.UnknownKernel(name) => assert_eq(name, "unknown")
    _ => fail("expected unregistered kernel failure")
  } noraise { _ => fail("accepted unknown kernel") }
}
