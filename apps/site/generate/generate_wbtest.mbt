///|
/// Under `moon test` the working directory is the module root, `apps/site`, so the fixture, the
/// assets and `_build/...` are relative to it.
async test "generate the fixture site" {
  let out = "_build/fixture-site"
  if @fs.exists(out) {
    @fs.rmdir(out, recursive=true)
  }
  let warnings = generate("fixtures/content", out, "assets", true)
  assert_eq(warnings, [])
  assert_eq(list_files(out), [
    "articles/atom.xml", "articles/first/index.html", "articles/index.html", "assets/site.css",
    "docs/diagram/index.html", "docs/guide/index.html", "docs/index.html", "index.html",
    "search-index.json",
  ])
  let guide = @fs.read_file("\{out}/docs/guide/index.html").text()
  assert_true(guide.contains("<h2 id=\"install\">Install</h2>"))
  assert_true(guide.contains("class=\"language-moonbit\""))
  assert_true(guide.contains("Proposed — not implemented"))
  assert_true(guide.contains("<aside class=\"callout note\">"))
  assert_true(guide.contains("<figure class=\"layer-stack\">"))
  assert_true(guide.contains("<span class=\"badge\">Proposed</span>"))
  let readme = @fs.read_file("\{out}/docs/index.html").text()
  assert_true(readme.contains("href=\"/fixture/docs/guide/#install\""))
  let diagram = @fs.read_file("\{out}/docs/diagram/index.html").text()
  assert_true(diagram.contains("<figure class=\"diagram\"><svg"))
  let home = @fs.read_file("\{out}/index.html").text()
  assert_true(home.has_prefix("<!DOCTYPE html><html data-base=\"/fixture/\""))
  assert_true(home.contains("href=\"/fixture/articles/first/\""))
  assert_true(home.contains("href=\"/fixture/docs/\""))
  let feed = @fs.read_file("\{out}/articles/atom.xml").text()
  assert_true(
    feed.contains("<id>https://example.org/fixture/articles/first/</id>"),
  )
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
  let problems = try generate(root, "\{root}/_site", "assets", false) catch {
    @model.Invalid(problems) => problems.map(p => p.render())
    error => [error.to_string()]
  } noraise {
    _ => []
  }
  assert_eq(problems, ["site/site.json: `base_path` must start and end with `/`"])
}

///|
/// A repository with a plan below `docs/superpowers/`, outside this repository.
async fn plan_repository() -> String {
  let root = @fs.tmpdir(prefix="lander-site-plans")
  @fs.mkdir("\{root}/site/pages", recursive=true)
  @fs.mkdir("\{root}/docs/superpowers", recursive=true)
  @fs.write_file(
    "\{root}/site/site.json",
    "{\"title\":\"t\",\"description\":\"d\",\"base_path\":\"/x/\",\"site_url\":\"https://e/x/\",\"repo_url\":\"r\"}",
  )
  @fs.write_file("\{root}/site/pages/index.html", "<h1>x</h1>")
  @fs.write_file("\{root}/docs/superpowers/plan.md", "# Plan\n")
  let (code, _, _) = @process.collect_output("git", ["init", "-q"], cwd=root)
  assert_eq(code, 0)
  root
}

///|
async test "Locally excluded plans" {
  let root = plan_repository()
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    "\{root}/.git/info/exclude",
    "docs/superpowers/\n",
    create_mode=CreateOrTruncate,
  )
  let warnings = generate(root, "\{root}/_out", "assets", true)
  assert_eq(warnings, [])
  assert_false(@fs.exists("\{root}/_out/docs/superpowers"))
}

///|
async test "Plan not excluded" {
  let root = plan_repository()
  defer @fs.rmdir(root, recursive=true)
  let problems = try generate(root, "\{root}/_out", "assets", true) catch {
    @model.Invalid(problems) => problems.map(p => p.render())
    error => [error.to_string()]
  } noraise {
    _ => []
  }
  assert_eq(problems, [
    "docs/superpowers/plan.md: forbidden path: agent specs, plans and ledgers live in beads",
  ])
}
