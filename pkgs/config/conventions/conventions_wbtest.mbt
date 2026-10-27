///|
/// The parsed path of the test path `text`.
fn wp(text : String) -> @config.FileTreePath {
  @config.FileTreePath::parse(text) catch {
    _ => abort("invalid test path \{text}")
  }
}

///|
test "parent directories stop at a root" {
  let walk = (dir : String) => {
    let dirs = [dir]
    let mut current = wp(dir)
    while current.parent() is Some(parent) {
      dirs.push(parent.to_string())
      current = parent
    }
    dirs
  }
  assert_eq(walk("/w/src/nested"), ["/w/src/nested", "/w/src", "/w", "/"])
  assert_eq(walk("C:/w/src"), ["C:/w/src", "C:/w", "C:/"])
  assert_eq(walk("//server/share/w"), ["//server/share/w", "//server/share"])
  assert_eq(walk("relative"), ["relative", "."])
}

///|
test "a trailing slash goes, except at a root" {
  assert_eq(wp("/w/src/").to_string(), "/w/src")
  assert_eq(wp("/").to_string(), "/")
  assert_eq(wp("C:/").to_string(), "C:/")
}

///|
test "discovery applies the parent names of the paths that a run gives" {
  let normal = (text : String) => normalize(wp(text)).to_string() catch {
    _ => abort("normalize failed")
  }
  assert_eq(normal("/w/a/b/."), "/w/a/b")
  assert_eq(normal("/w/a/b/../c/"), "/w/a/c")
  assert_eq(normal("/w/../.."), "/")
  assert_eq(normal("C:/w/./x/.."), "C:/w")
  assert_eq(normal("C:/"), "C:/")
  assert_eq(normal("//server/share/w/.."), "//server/share")
}

///|
test "Windows absolute paths have a drive and a separator, or a UNC prefix" {
  let absolute = (text : String, platform : @config.Platform) => {
    input_path(text, Some(platform)).is_absolute() catch {
      _ => false
    }
  }
  assert_eq(absolute("C:/Users", Windows), true)
  assert_eq(absolute("d:/", Windows), true)
  assert_eq(absolute("C:\\Users", Windows), true)
  assert_eq(absolute("//server/share", Windows), true)
  assert_eq(absolute("\\\\server\\share", Windows), true)
  assert_eq(absolute("1:/x", Windows), false)
  assert_eq(absolute("Users", Windows), false)
  assert_eq(absolute("/home", Linux), true)
  // A drive-relative path is not a path that discovery can place.
  try input_path("C:foo", Some(Windows)) catch {
    InvalidFilePath(rule~, ..) => assert_eq(rule, DriveRelative)
    _ => fail("expected an invalid-path error")
  } noraise {
    _ => fail("C:foo is relative to the current directory of drive C")
  }
}
