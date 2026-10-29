///|
test "local paths reject empty and NUL input" {
  assert_eq(@policy.LocalPath::parse(".").text(), ".")
  assert_eq(@policy.LocalPath::parse("/tmp/site").text(), "/tmp/site")
  for value in ["", "a\u{0}b"] {
    let failed = try { ignore(@policy.LocalPath::parse(value)); false } catch { _ => true }
    assert_true(failed)
  }
}

///|
test "ports enforce both boundaries and decimal syntax" {
  assert_eq(@policy.Port::parse("1").number(), 1)
  assert_eq(@policy.Port::parse("65535").number(), 65535)
  for value in ["0", "65536", "-1", "+1", "", "x", "999999999999999999999"] {
    let failed = try { ignore(@policy.Port::parse(value)); false } catch { _ => true }
    assert_true(failed)
  }
}

///|
test "tree prefixes are root, next or one minor line" {
  for value in ["", "next/", "v/0.7/", "v/123.456/"] {
    assert_eq(@policy.TreePrefix::parse(value).text(), value)
  }
  for value in ["next", "latest/", "v/1/", "v/1.2.3/", "v/a.2/", "../", "v/.2/", "v/1./"] {
    let failed = try { ignore(@policy.TreePrefix::parse(value)); false } catch { _ => true }
    assert_true(failed)
  }
}

///|
test "base paths are normalized and absolute" {
  for value in ["/", "/moon-lander/", "/moon-lander/next/"] {
    assert_eq(@policy.BasePath::parse(value).text(), value)
  }
  for value in ["", "x/", "/x", "/x//", "/../", "/./", "/x%20/", "/x?y/", "/x#y/", "/x\\y/", "/x\u{0}/"] {
    let failed = try { ignore(@policy.BasePath::parse(value)); false } catch { _ => true }
    assert_true(failed)
  }
}

///|
test "command parsing returns typed values and rejects unknown or incomplete options" {
  guard @policy.Command::parse(["build", "--tree-path", "next/", "--main"]) is Build(root, out, tree, main_build) else {
    fail("expected build")
  }
  assert_eq(root.text(), ".")
  assert_eq(out.text(), "_site")
  assert_eq(tree.text(), "next/")
  assert_true(main_build)
  guard @policy.Command::parse(["serve", "--port", "1"]) is Serve(_, _, port) else { fail("expected serve") }
  assert_eq(port.number(), 1)
  for args in [[], ["other"], ["build", "--oops", "x"], ["check", "--main"], ["build", "--out"], ["serve", "--port", "0"]] {
    let failed = try { ignore(@policy.Command::parse(args)); false } catch { _ => true }
    assert_true(failed)
  }
}
