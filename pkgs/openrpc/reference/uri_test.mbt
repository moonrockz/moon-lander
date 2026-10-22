///|
test "URI references retain structured components and generic fragments" {
  let text = "HTTPS://user:pass@Example.COM:000443/a%2fb?x=1?2#/not~2-a-pointer"
  let uri = @reference.UriReference::parse(text).unwrap()
  assert_eq(uri.text(), text)
  assert_eq(uri.scheme(), Some("HTTPS"))
  assert_eq(uri.path(), "/a%2fb")
  assert_eq(uri.query(), Some("x=1?2"))
  assert_eq(uri.fragment(), Some("/not~2-a-pointer"))
  assert_true(uri.is_absolute())
  let authority = uri.authority().unwrap()
  assert_eq(authority.userinfo(), Some("user:pass"))
  assert_eq(authority.port(), Some("000443"))
  guard authority.host() is @reference.RegisteredName(host) else {
    fail("host")
  }
  assert_eq(host, "Example.COM")
  assert_eq(
    uri.without_fragment().text(),
    "HTTPS://user:pass@Example.COM:000443/a%2fb?x=1?2",
  )
  assert_true(@reference.Reference::parse(text) is Err(_))
  assert_true(
    @reference.UriReference::parse("https://example.test/#%FF") is Ok(_),
  )
  for
    (text, query, fragment) in [
      ("", None, None),
      ("?", Some(""), None),
      ("#", None, Some("")),
      ("?#", Some(""), Some("")),
    ] {
    let uri = @reference.UriReference::parse(text).unwrap()
    assert_eq(uri.query(), query)
    assert_eq(uri.fragment(), fragment)
    assert_false(uri.is_absolute())
  }
}

///|
test "generic URI authority accepts literal IP forms and exact port tokens" {
  for
    text in [
      "file:///a", "mailto:person@example.test", "urn:example:a:b", "//host/path",
      "http://[::1]/", "http://[2001:db8::1]:80/", "http://[::ffff:192.0.2.1]/",
      "http://[1:2:3:4:5:6:7:8]/", "http://[v1.alpha:beta]/", "http://user@host:/",
      "http://127.0.0.1/", "http://host:999999999999999999999999/", "/a:b", "a/b:c",
    ] {
    assert_true(@reference.UriReference::parse(text) is Ok(_), msg=text)
  }
  guard @reference.UriReference::parse("http://[::1]/")
    .unwrap()
    .authority()
    .unwrap()
    .host()
    is @reference.Ipv6(host) else {
    fail("ipv6")
  }
  assert_eq(host, "::1")
  guard @reference.UriReference::parse("http://127.0.0.1/")
    .unwrap()
    .authority()
    .unwrap()
    .host()
    is @reference.Ipv4(_) else {
    fail("ipv4")
  }
  for
    text in [
      "1scheme:value", ":value", "a b", "https://é.example/", "http://host:abc/",
      "http://a@b@host/", "http://[::1", "http://[::1]x", "http://[::1]:a", "http://[1:2:3:4:5:6:7]/",
      "http://[1:2:3:4:5:6:7:8:9]/", "http://[1::2::3]/", "http://[::ffff:192.0.2.999]/",
      "http://[v.alpha]/", "http://[v1.]/", "http://[fe80::1%25en0]/", "http://a:b:c/",
      "a[0]", "a#b#c", "a?b[c]", "a%", "a%2X", "a\\b", "a{b}",
    ] {
    guard @reference.UriReference::parse(text) is Err(d) else { fail(text) }
    assert_eq(d.code(), @json.InvalidReference, msg=text)
  }
}

///|
test "RFC3986 relative resolution retains component spelling" {
  let base = @reference.UriReference::parse("http://a/b/c/d;p?q").unwrap()
  for
    (text, expected) in [
      ("g:h", "g:h"),
      ("g", "http://a/b/c/g"),
      ("./g", "http://a/b/c/g"),
      ("g/", "http://a/b/c/g/"),
      ("/g", "http://a/g"),
      ("//g", "http://g"),
      ("?y", "http://a/b/c/d;p?y"),
      ("#s", "http://a/b/c/d;p?q#s"),
      ("g?y#s", "http://a/b/c/g?y#s"),
      (";x", "http://a/b/c/;x"),
      ("", "http://a/b/c/d;p?q"),
      (".", "http://a/b/c/"),
      ("..", "http://a/b/"),
      ("../g", "http://a/b/g"),
      ("../../g", "http://a/g"),
      ("../../../g", "http://a/g"),
      ("/./g", "http://a/g"),
      ("/../g", "http://a/g"),
      ("g.", "http://a/b/c/g."),
      (".g", "http://a/b/c/.g"),
      ("g/./h", "http://a/b/c/g/h"),
      ("g/../h", "http://a/b/c/h"),
      ("g?y/../x", "http://a/b/c/g?y/../x"),
      ("g#s/../x", "http://a/b/c/g#s/../x"),
      ("http:g", "http:g"),
    ] {
    let uri = @reference.UriReference::parse(text).unwrap()
    assert_eq(uri.resolve(base).unwrap().text(), expected, msg=text)
  }
  let base = @reference.UriReference::parse("HTTPS://Example.test").unwrap()
  assert_eq(
    @reference.UriReference::parse("x%2fy")
    .unwrap()
    .resolve(base)
    .unwrap()
    .text(),
    "HTTPS://Example.test/x%2fy",
  )
}

///|
test "URI identity normalization is separate from source and reserved escapes" {
  let uri = @reference.UriReference::parse(
    "HTTP://%45XAMPLE.com/a/%2e%2e/b/%7euser?q=%2f#%61",
  ).unwrap()
  assert_eq(uri.identity(), "http://example.com/b/~user?q=%2F#a")
  assert_eq(uri.text(), "HTTP://%45XAMPLE.com/a/%2e%2e/b/%7euser?q=%2f#%61")
  assert_eq(
    @reference.UriReference::parse("http://EXAMPLE.com/a//b/./")
    .unwrap()
    .identity(),
    "http://example.com/a//b/",
  )
  assert_true(
    @reference.UriReference::parse("http://example.com:80/").unwrap().identity() !=
    @reference.UriReference::parse("http://example.com/").unwrap().identity(),
  )
  assert_true(
    @reference.UriReference::parse("a%2Fb").unwrap().identity() !=
    @reference.UriReference::parse("a/b").unwrap().identity(),
  )
  assert_eq(@reference.UriReference::parse("../g").unwrap().identity(), "../g")
}

///|
test "URI parsing and resolution have typed bounds" {
  guard @reference.UriReference::parse(
      "abcdef",
      limits=@json.Limits::new(max_source=5),
    )
    is Err(d) else {
    fail("limit")
  }
  assert_eq(d.code(), @json.LimitExceeded)
  let uri = @reference.UriReference::parse("relative").unwrap()
  let base = @reference.UriReference::parse("also-relative").unwrap()
  assert_true(uri.resolve(base) is Err(_))
  let base = @reference.UriReference::parse("https://example.test/a/").unwrap()
  guard uri.resolve(base, limits=@json.Limits::new(max_source=10)) is Err(d) else {
    fail("resolved length")
  }
  assert_eq(d.code(), @json.LimitExceeded)
}
