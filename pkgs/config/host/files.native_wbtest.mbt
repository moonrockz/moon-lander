///|
test "a listed entry joins its native directory with the name as given" {
  assert_eq(native_join("C:\\w", "a.toml", Windows), "C:\\w\\a.toml")
  assert_eq(native_join("C:\\", "a.toml", Windows), "C:\\a.toml")
  // A Linux name can hold `\`. It is no file-tree path, but it can be inspected.
  assert_eq(native_join("/w", "a\\b", Linux), "/w/a\\b")
  assert_eq(native_join("/", "a", Linux), "/a")
}
