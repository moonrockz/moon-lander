///|
test "parent directories stop at a root" {
  let walk = (dir : String) => {
    let dirs = [dir]
    let mut current = dir
    while parent_dir(current) is Some(parent) {
      dirs.push(parent)
      current = parent
    }
    dirs
  }
  assert_eq(walk("/w/src/nested"), ["/w/src/nested", "/w/src", "/w", "/"])
  assert_eq(walk("C:/w/src"), ["C:/w/src", "C:/w", "C:/"])
  assert_eq(walk("//server/share/w"), ["//server/share/w", "//server/share"])
  assert_eq(walk("relative"), ["relative"])
}

///|
test "a trailing slash goes, except at a root" {
  assert_eq(trim_dir("/w/src/"), "/w/src")
  assert_eq(trim_dir("/"), "/")
  assert_eq(trim_dir("C:/"), "C:/")
}

///|
test "paths normalize dot segments" {
  assert_eq(normalize("/w/a/b/."), "/w/a/b")
  assert_eq(normalize("/w/a/b/../c/"), "/w/a/c")
  assert_eq(normalize("/w/../.."), "/")
  assert_eq(normalize("C:/w/./x/.."), "C:/w")
  assert_eq(normalize("C:/"), "C:/")
  assert_eq(normalize("//server/share/w/.."), "//server/share")
}
