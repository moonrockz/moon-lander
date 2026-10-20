///|
/// Under `moon test` the working directory is the module root, `apps/site`, so the fixture, the
/// assets and `_build/fixture-site` are relative to it.
async test "generate writes the landing page and the assets" {
  let out = "_build/fixture-site"
  if @fs.exists(out) {
    @fs.rmdir(out, recursive=true)
  }
  generate("fixtures/content", out, "assets")
  assert_eq(@fs.readdir(out, sort=true), ["assets", "index.html"])
  assert_eq(@fs.readdir("\{out}/assets", sort=true), ["site.css"])
  let home = @fs.read_file("\{out}/index.html").text()
  assert_true(home.has_prefix("<!DOCTYPE html><html data-base=\"/fixture/\""))
  assert_true(home.contains("<title>Fixture site</title>"))
  assert_true(home.contains("href=\"/fixture/assets/site.css\""))
  assert_true(home.contains("<a href=\"/fixture/\" target=\"_self\" class=\"brand\">"))
  assert_true(home.contains("<h1>Fixture</h1>"))
}

///|
async test "a bad configuration fails the build" {
  let root = "_build/bad-config"
  if @fs.exists(root) {
    @fs.rmdir(root, recursive=true)
  }
  @fs.mkdir("\{root}/site/pages", recursive=true)
  @fs.write_file(
    "\{root}/site/site.json",
    "{\"title\":\"t\",\"description\":\"d\",\"base_path\":\"/x\",\"site_url\":\"https://e/\",\"repo_url\":\"r\"}",
  )
  @fs.write_file("\{root}/site/pages/index.html", "<h1>x</h1>")
  let problems = try generate(root, "\{root}/_site", "assets") catch {
    @model.Invalid(problems) => problems.map(p => p.render())
    error => [error.to_string()]
  } noraise {
    _ => []
  }
  assert_eq(problems, ["site/site.json: `base_path` must start and end with `/`"])
  assert_false(@fs.exists("\{root}/_site/index.html"))
}
