///|
test "API index markers follow root, project and next bases" {
  let html = "<a href=\"moon-lander-route://api-index\">API</a><a href=\"https://example.test/\">External</a>"
  for base in ["/", "/moon-lander/", "/moon-lander/next/"] {
    let result = resolve_api_index("index.html", html, @policy.BasePath::parse(base))
    assert_true(result.contains("href=\"\{base}api/\""))
    assert_true(result.contains("href=\"https://example.test/\""))
    assert_false(result.contains("moon-lander-route://"))
  }
}

///|
test "unknown compatibility routes fail with their source" {
  let problems = try {
    ignore(resolve_api_index("docs/guide/index.html", "<a href=\"moon-lander-route://typo\">Bad</a>", @policy.BasePath::parse("/")))
    []
  } catch { @model.Invalid(problems) => problems; error => fail("unexpected: \{error}") }
  assert_eq(problems.length(), 1)
  assert_eq(problems[0].file, "docs/guide/index.html")
}

///|
async test "compatibility links require an actual generated API index" {
  let out = @fs.tmpdir(prefix="lander-api-index")
  defer @fs.rmdir(out, recursive=true)
  write(out, "index.html", "<!doctype html><html><head><title>Home</title></head><body><a href=\"moon-lander-route://api-index\">API</a></body></html>")
  let problems = try {
    finish_api_links(out, @policy.BasePath::parse("/example/"))
    []
  } catch { @model.Invalid(problems) => problems; error => fail("unexpected: \{error}") }
  assert_eq(problems.length(), 1)
  write(out, "api/index.html", "<!doctype html><html><head><title>API</title></head><body>API</body></html>")
  finish_api_links(out, @policy.BasePath::parse("/example/"))
  assert_eq(@host.check(out, "/example/"), [])
  let html = @fs.read_file(out + "/index.html").text()
  assert_true(html.contains("href=\"/example/api/\""))
  assert_false(html.contains("moon-lander-route://"))
}
