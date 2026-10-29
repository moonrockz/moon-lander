///|
test "tree paths parse every rule and retain valid relative names" {
  for (input, rule) in [
    ("", @files.Empty), ("/a", @files.Absolute),
    ("C:/a", @files.Absolute), ("C:a", @files.Absolute),
    ("a\\b", @files.Backslash), ("a\u{0}b", @files.ControlCharacter),
    ("a\nb", @files.ControlCharacter), ("a\rb", @files.ControlCharacter),
    ("a//b", @files.EmptySegment), ("a/", @files.EmptySegment),
    ("./a", @files.DotSegment), ("a/../b", @files.DotSegment),
  ] {
    try @files.TreePath::parse(input) catch {
      @files.InvalidPath(input=actual, rule=actual_rule) => {
        assert_eq(actual, input)
        assert_eq(actual_rule, rule)
      }
      _ => fail("unexpected path error")
    } noraise { _ => fail("accepted invalid path: " + input) }
  }
  for text in ["a", "a/b", "a b/c d", "..hidden", "a.b", "日本語/file", "quoted\"name"] {
    assert_eq(@files.TreePath::parse(text).to_string(), text)
  }
  assert_eq(@files.TreePath::parse("a").parent(), None)
  assert_eq(@files.TreePath::parse("a/b").parent(), Some(@files.TreePath::parse("a")))
}

///|
test "immutable trees infer parents preserve empty directories and normalize text" {
  let path = @files.TreePath::parse("src/main.mbt")
  let empty = @files.TreePath::parse("fixtures/empty")
  let file = @files.TextFile::new(path, "\r\n42\r", kernel=@dib.KernelName("moonbit"))
  let files = [file]
  let tree = @files.FileTree::new(ReadOnlyArray::from_array(files[:]), directories=[empty, empty])
  files.clear()
  assert_eq(tree.files().length(), 1)
  assert_eq(tree.file(path), Some(file))
  assert_eq(tree.file(empty), None)
  assert_eq(file.source(), "\n42\n")
  assert_eq(tree.explicit_directories(), [empty])
  assert_true(tree.directories().contains(@files.TreePath::parse("src")))
  assert_true(tree.directories().contains(@files.TreePath::parse("fixtures")))
}

///|
test "tree construction refuses duplicates and every file directory conflict" {
  let a = @files.TreePath::parse("a")
  let file = @files.TextFile::new(a, "", kernel=@dib.KernelName("text"))
  try @files.FileTree::new([file, file]) catch {
    @files.DuplicatePath(path) => assert_eq(path, a)
    _ => fail("expected duplicate path")
  } noraise { _ => fail("accepted duplicate") }
  for dirs in [[a], [@files.TreePath::parse("a/b")]] {
    try @files.FileTree::new([file], directories=ReadOnlyArray::from_array(dirs[:])) catch {
      @files.FileDirectoryConflict(path) => assert_eq(path, a)
      _ => fail("expected directory conflict")
    } noraise { _ => fail("accepted directory conflict") }
  }
  let child = @files.TextFile::new(@files.TreePath::parse("a/b"), "", kernel=@dib.KernelName("text"))
  try @files.FileTree::new([file, child]) catch {
    @files.FileDirectoryConflict(path) => assert_eq(path, a)
    _ => fail("expected inferred parent conflict")
  } noraise { _ => fail("accepted parent conflict") }
}
