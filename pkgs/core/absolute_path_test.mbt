///|
test "absolute paths accept roots and normalize Windows separators" {
  for (text, expected) in [
    ("/tmp/a\\b", "/tmp/a\\b"), ("/\\x", "/\\x"),
    ("C:\\w", "C:/w"), ("C:/w\\x", "C:/w/x"),
    ("\\\\server\\share\\x", "//server/share/x"),
    ("/w/", "/w/"), ("/a/./b", "/a/./b"), ("//s/h/", "//s/h/"),
    ("/", "/"), ("/w", "/w"), ("/a/../b", "/a/../b"),
    ("C:/", "C:/"), ("z:/work", "z:/work"), ("C:\\work\\repo", "C:/work/repo"),
    ("\\\\server\\share", "//server/share"),
  ] {
    let path = @lander_core.AbsolutePath::parse(text)
    assert_eq(path.to_string(), expected)
    assert_eq(path, @lander_core.AbsolutePath::parse(expected))
  }
  assert_eq(@lander_core.AbsolutePath::root().to_string(), "/")
}

///|
test "absolute path rules reject empty and relative paths" {
  for text in [
    "",
    "w", ".", "../w",
    "C:", "C:w", "1:/w",
    "@:/w", "[:/w", "`:/w",
    "{:/w", "\\work",
  ] {
    try { ignore(@lander_core.AbsolutePath::parse(text)) } catch {
      InvalidAbsolutePath(text=found, rule~) as error => {
        assert_eq(found, text)
        assert_true(if text.is_empty() { rule is Empty } else { rule is NotAbsolute })
        assert_true(error.message().contains(text.escape()))
      }
    } noraise { _ => fail("expected a path error") }
  }
}

///|
test "UNC roots need a server and share" {
  for text in ["//", "\\\\", "//server", "//server/", "//server//x", "///share", "\\\\server"] {
    try { ignore(@lander_core.AbsolutePath::parse(text)) } catch {
      InvalidAbsolutePath(text=found, rule=MissingUncServerOrShare) as error => {
        assert_eq(found, text)
        assert_true(error.message().contains(text.escape()))
      }
      error => raise error
    } noraise { _ => fail("expected a UNC root error") }
  }
  for text in ["//s/h", "//server/share", "\\\\s\\h"] {
    ignore(@lander_core.AbsolutePath::parse(text))
  }
}
