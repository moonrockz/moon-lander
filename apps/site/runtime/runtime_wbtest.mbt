///|
async fn write(root : String, file : String, text : String) -> Unit {
  let path = "\{root}/\{file}"
  @fs.mkdir(@host.parent(path), recursive=true, allow_exist=true)
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
async fn fixture() -> String {
  let root = @fs.tmpdir(prefix="lander-telescope")
  let config = (
    #|{"title":"Fixture","description":"A site","base_path":"/fixture/","site_url":"https://example.test/fixture/","repo_url":"https://example.test/repo","source_roots":["docs","site/pages","site/articles","pkgs"]}
  )
  write(root, "site/site.json", config)
  write(root, "site/pages/index.html", "<h1>Fixture</h1><a href=\"/docs/\">Docs</a>")
  write(root, "docs/README.md", "# Docs\n\n[Guide](guide.md#install)\n")
  let guide = (
    #|---
    #|title: Guide
    #|status: proposed
    #|---
    #|# Guide
    #|
    #|## Install
    #|
    #|> [!NOTE]
    #|> Keep settings explicit.
    #|
    #|```moonbit notest
    #|let value = 1
    #|```
    #|
    #|```layers
    #|Overrides | flags
    #|Defaults | code
    #|```
    #|
    #|```mermaid
    #|graph LR
    #|A --> B
    #|```
  )
  write(root, "docs/guide.md", guide)
  ignore(git(root, ["init", "-q"]))
  ignore(git(root, ["-c", "user.name=Site fixture", "-c", "user.email=site@example.test", "commit", "--allow-empty", "-qm", "fixture"]))
  root
}

///|
async test "the shared host preserves content and active deployment bases" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  for suffix in ["", "next/"] {
    let config = effective_configuration(root, @policy.TreePrefix::parse(suffix))
    let out = "\{root}/out-\{suffix.replace_all(old="/", new="-")}"
    let warnings = build(root, config, out, main_build=true)
    assert_eq(warnings, [])
    assert_eq(@host.check(out, "/fixture/" + suffix), [])
    let html = @fs.read_file(out + "/docs/guide/index.html").text()
    assert_true(html.contains("id=\"install\""))
    assert_true(html.contains("Proposed — not implemented"))
    assert_true(html.contains("aside class=\"callout note\""))
    assert_true(html.contains("figure class=\"layer-stack\""))
    assert_true(html.contains("figure class=\"diagram\"><svg"))
    assert_true(html.contains("class=\"language-moonbit\""))
    assert_true(@fs.read_file(out + "/index.html").text().contains("href=\"/fixture/\{suffix}docs/\""))
  }
}

///|
async test "ignored pages and brand documentation are not discovered" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  write(root, ".git/info/exclude", "docs/ignored.md\ndocs/superpowers/\n")
  write(root, "docs/ignored.md", "# Ignored\n\n[bad](missing.md)")
  write(root, "docs/assets/brand/README.md", "# Brand\n\n[bad](missing.md)")
  write(root, "docs/assets/brand/preview.html", "<h1>Preview</h1>")
  write(root, "docs/superpowers/local.md", "# Local plan")
  let config = effective_configuration(root, @policy.TreePrefix::parse(""))
  let out = root + "/out"
  ignore(build(root, config, out))
  assert_false(@fs.exists(out + "/docs/ignored/index.html"))
  assert_false(@fs.exists(out + "/docs/assets/brand/index.html"))
  assert_false(@fs.exists(out + "/docs/superpowers/local/index.html"))
}

///|
async test "a tracked or unexcluded scratch plan fails before rendering" {
  let root = fixture()
  defer @fs.rmdir(root, recursive=true)
  write(root, "docs/superpowers/plan.md", "# Plan")
  let problems = try {
    ignore(effective_configuration(root, @policy.TreePrefix::parse("")))
    []
  } catch { @model.Invalid(problems) => problems; error => fail("unexpected error: \{error}") }
  assert_eq(problems.length(), 1)
  assert_eq(problems[0].file, "docs/superpowers/")
}

///|
async test "invalid prose and diagram inputs still fail with the source" {
  for (file, body) in [
    ("bad.md", "# Bad\n\n[broken](missing.md)"),
    ("code.md", "# Bad\n\n" + "```moonbit\nlet x = 1\n```"),
    ("diagram.md", "# Bad\n\n" + "```mermaid\ngantt\ntitle bad\n```"),
    ("layers.md", "# Bad\n\n" + "```layers\nmissing separator\n```"),
    ("draft.md", "---\ndraft: true\n---\n# Draft"),
  ] {
    let root = fixture()
    defer @fs.rmdir(root, recursive=true)
    write(root, "docs/" + file, body)
    let config = effective_configuration(root, @policy.TreePrefix::parse(""))
    let problems = try {
      ignore(build(root, config, root + "/out", main_build=true))
      []
    } catch { @model.Invalid(problems) => problems; error => fail("unexpected error: \{error}") }
    if problems.is_empty() { fail("expected a build failure for \{file}") }
    assert_true(problems.iter().any(p => p.file.contains(file)))
  }
}
