///|
/// `fixtures/api/doc` holds `moon doc` output of `pkgs/notebooks`, cut down to a few items.
async test "Item without a docstring" {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file("fixtures/api/site/site.json").text(),
  )
  let warnings = api_warnings("fixtures/api/doc", config).map(w => w.render())
  assert_true(
    warnings.contains("moonrockz/notebooks: `#CellKind.equal` has no docstring"),
  )
  assert_false(
    warnings.contains("moonrockz/notebooks: `#CellKind` has no docstring"),
  )
}

///|
async test "a module without moon doc output gives one warning" {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file("fixtures/api/site/site.json").text(),
  )
  assert_eq(
    api_warnings("fixtures/no-such-dir", config).map(w => w.render()),
    [
      "site/site.json: `api` lists `pkgs/notebooks`, but fixtures/no-such-dir/pkgs/notebooks/doc has no `moon doc` output",
    ],
  )
}
