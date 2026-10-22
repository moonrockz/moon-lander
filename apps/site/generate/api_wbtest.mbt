///|
/// `fixtures/api/doc` holds `moon doc` output of `pkgs/notebooks`, cut down to a few items.
async test "Package page" {
  let out = "_build/fixture-api"
  if @fs.exists(out) {
    @fs.rmdir(out, recursive=true)
  }
  let warnings = generate(
    "fixtures/api",
    out,
    "assets",
    true,
    api_dir="fixtures/api/doc",
  )
  assert_eq(warnings, [])
  let files = list_files(out)
  assert_true(files.contains("api/index.html"))
  assert_true(files.contains("api/moonrockz/notebooks/index.html"))
  let page = @fs.read_file("\{out}/api/moonrockz/notebooks/index.html").text()
  let types = page.find("<h2 id=\"api-types\">Types</h2>").unwrap()
  let values = page.find("<h2 id=\"api-values\">Values</h2>").unwrap()
  let cell_kind = page.find("<h3 id=\"CellKind\"").unwrap()
  assert_true(types < cell_kind && cell_kind < values)
  // Method anchor
  assert_true(page.contains("id=\"CellKind.equal\""))
  assert_true(page.contains("id=\"Metadata.Eq.equal\""))
  // Empty section
  assert_false(page.contains("Type aliases"))
  assert_false(page.contains("id=\"api-errors\""))
  // Signature text, same package and a package outside the site
  assert_true(page.contains("-&gt; N?"))
  assert_true(page.contains("<a href=\"#CellKind\">CellKind</a>::equal"))
  assert_false(page.contains("href=\"moonbitlang/core/builtin#Eq\""))
  // Docstring and source link
  assert_true(
    page.contains(
      "<div class=\"api-doc\"><p>The common role of a cell, independent of its file format.",
    ),
  )
  let commit = head_commit(".")
  assert_true(
    page.contains(
      "href=\"https://example.org/repo/blob/\{commit}/pkgs/notebooks/navigation.mbt#L4\"",
    ),
  )
  // Index
  let index = @fs.read_file("\{out}/api/index.html").text()
  assert_true(index.contains("href=\"/fixture/api/moonrockz/notebooks/\""))
  assert_true(index.contains("Immutable notebook models with shared navigation."))
  assert_true(index.contains("href=\"/fixture/api/\""))
}

///|
async test "a module in api without moon doc output fails the build" {
  let message = try
    generate(
      "fixtures/api",
      "_build/fixture-api-missing",
      "assets",
      true,
      api_dir="fixtures/no-such-dir",
    )
    |> ignore
  catch {
    @model.Invalid(problems) => problems.map(p => p.render()).join("\n")
    error => "\{error}"
  } noraise {
    _ => ""
  }
  assert_eq(
    message, "site/site.json: `api` lists `pkgs/notebooks`, but fixtures/no-such-dir/pkgs/notebooks/doc has no `moon doc` output; run `mise run build:site`",
  )
}
