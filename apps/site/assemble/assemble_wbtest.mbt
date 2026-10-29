///|
/// One line of `gh api --paginate` output with `releases_filter`.
fn release_line(
  tag : String,
  assets~ : String = "",
  draft~ : Bool = false,
  prerelease~ : Bool = false,
) -> String {
  "\{tag}\t\{draft}\t\{prerelease}\t\{assets}"
}

///|
fn tags(releases : Array[Release]) -> Array[String] {
  releases.map(release => release.tag)
}
///|
async test "the retained v0.7.3 archive assembles without changing its browser assets" {
  let dir = @fs.tmpdir(prefix="lander-retained-site")
  defer @fs.rmdir(dir, recursive=true)
  unpack("v0.7.3", "fixtures/versioned/site-0.7.tar.gz", dir + "/v/0.7")
  let js = @fs.read_file(dir + "/v/0.7/assets/islands.js").binary()
  let search = @fs.read_file(dir + "/v/0.7/search-index.json").binary()
  assert_eq(@host.check(dir + "/v/0.7", "/moon-lander/v/0.7/"), [])
  write_text(dir + "/next/index.html",
    tree_page("/moon-lander/next/", "").replace_all(old="data-site-root=\"/m/\"", new="data-site-root=\"/moon-lander/\""))
  write_text(dir + "/next/assets/site.css", "a{}")
  write_text(dir + "/next/search-index.json", "[]")
  assemble_site(dir, { base: "/moon-lander/", site_url: "https://moonrockz.github.io/moon-lander/", lines: ["0.7"] })
  assert_eq(@host.check(dir, "/moon-lander/"), [])
  for tree in ["", "latest/", "v/0.7/"] {
    assert_eq(@fs.read_file(dir + "/" + tree + "assets/islands.js").binary(), js)
    assert_eq(@fs.read_file(dir + "/" + tree + "search-index.json").binary(), search)
    let api = @fs.read_file(dir + "/" + tree + "api/moonrockz/notebooks/index.html").text()
    assert_true(api.contains("id=\"CellKind\""))
    let home = @fs.read_file(dir + "/" + tree + "index.html").text()
    assert_true(home.contains("data-base=\"/moon-lander/\{tree}\""))
  }
  let next = @fs.read_file(dir + "/next/index.html").text()
  assert_true(next.contains("which is not released. The latest is 0.7"))
  assert_true(next.contains("https://moonrockz.github.io/moon-lander/latest/"))
  assert_eq(@fs.read_file(dir + "/next/search-index.json").text(), "[]")
}

///|
test "Patch release" {
  let text = [
    release_line("v0.1.3", assets="site-0.1.tar.gz"),
    release_line("v0.1.2", assets="site-0.1.tar.gz"),
  ].join("\n")
  assert_eq(tags(select_releases(parse_releases(text), "0.1")), ["v0.1.3"])
}

///|
test "Release before site assets" {
  let text = [release_line("v0.2.0"), release_line("v0.1.0")].join("\n")
  assert_eq(select_releases(parse_releases(text), "0.3"), [])
}

///|
test "More than 30 releases" {
  let lines = []
  for patch = 38; patch >= 0; patch = patch - 1 {
    lines.push(release_line("v0.5.\{patch}", assets="site-0.5.tar.gz"))
  }
  for patch = 5; patch >= 0; patch = patch - 1 {
    lines.push(release_line("v0.2.\{patch}", assets="site-0.2.tar.gz"))
  }
  assert_eq(lines.length(), 45)
  assert_eq(lines[39], release_line("v0.2.5", assets="site-0.2.tar.gz"))
  let selected = select_releases(parse_releases(lines.join("\n")), "0.2")
  assert_eq(tags(selected), ["v0.5.38", "v0.2.5"])
}

///|
test "drafts, prereleases and other tags are left out" {
  let text = [
    release_line("v0.4.0", draft=true),
    release_line("v0.4.0-rc.1", prerelease=true),
    release_line("v0.3.1", prerelease=true),
    release_line("v0.3.0", assets="notes.txt,site-0.3.tar.gz"),
    release_line("nightly"),
  ].join("\n")
  let selected = select_releases(parse_releases(text), "0.3")
  assert_eq(tags(selected), ["v0.3.0"])
  assert_eq(selected[0].assets, ["notes.txt", "site-0.3.tar.gz"])
  assert_eq(missing_assets(selected), [])
}

///|
test "Missing asset" {
  let text = [
    release_line("v0.4.0"),
    release_line("v0.3.0", assets="site-0.3.tar.gz"),
  ].join("\n")
  let selected = select_releases(parse_releases(text), "0.3")
  assert_eq(missing_assets(selected).map(p => p.render()), [
    "v0.4.0: the release has no site asset `site-0.4.tar.gz`",
  ])
}

///|
test "versions.since comes from site.json" {
  assert_eq(versions_since("{\"versions\": {\"since\": \"0.3\"}}"), "0.3")
  let message = try versions_since("{}") catch {
    @model.Invalid(problems) => problems[0].render()
  } noraise {
    _ => ""
  }
  assert_eq(
    message, "site/site.json: `versions.since` must be a minor line, such as \"0.3\"",
  )
}

///|
/// A clean directory below `_build/` for one test. Under `moon test` the working directory is the
/// module root, `apps/site`.
async fn test_dir(name : String) -> String {
  let dir = "_build/assemble-\{name}"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  @fs.mkdir(dir, recursive=true)
  dir
}

///|
async test "fixture archive unpacks, and a corrupt one names the release" {
  let dir = test_dir("archive")
  write_text("\{dir}/tree/index.html", "<p>0.3</p>")
  let (code, _, _) = @process.collect_output("tar", [
    "-czf",
    "\{dir}/site-0.3.tar.gz",
    "-C",
    "\{dir}/tree",
    ".",
  ])
  assert_eq(code, 0)
  unpack("v0.3.0", "\{dir}/site-0.3.tar.gz", "\{dir}/out")
  assert_eq(@fs.read_file("\{dir}/out/index.html").text(), "<p>0.3</p>")
  write_text("\{dir}/bad.tar.gz", "not an archive")
  let message = try unpack("v0.3.1", "\{dir}/bad.tar.gz", "\{dir}/bad") catch {
    @model.Invalid(problems) => problems[0].file
    _ => "another error"
  } noraise {
    _ => "no error"
  }
  assert_eq(message, "v0.3.1")
}

///|
/// A page of a tree with the base path `base`, the empty banner and a link to `link` below the base.
fn tree_page(base : String, link : String) -> String {
  "<!DOCTYPE html><html data-base=\"\{base}\" data-site-root=\"/m/\"><head><title>T</title><link href=\"\{base}assets/site.css\" rel=\"stylesheet\"></head><body><div class=\"version-banner\"></div><a href=\"\{base}\{link}\">x</a></body></html>"
}

///|
/// Write a tree below `dir` at `path` with the base path `/m/<path>` and the pages `routes`.
async fn write_tree(dir : String, path : String, routes : Array[String]) -> Unit {
  let base = "/m/\{path}"
  for route in routes {
    write_text("\{dir}/\{path}\{route}index.html", tree_page(base, route))
  }
  write_text("\{dir}/\{path}assets/site.css", "a{}")
  write_text("\{dir}/\{path}search-index.json", "[{\"route\":\"/docs/\"}]")
}

///|
async test "No release" {
  let dir = test_dir("no-release")
  write_tree(dir, "next/", ["", "docs/"])
  assemble_site(dir, { base: "/m/", site_url: "https://e.org/m/", lines: [] })
  let root = @fs.read_file("\{dir}/index.html").text()
  assert_true(root.contains("data-base=\"/m/\""))
  assert_true(root.contains("href=\"/m/assets/site.css\""))
  assert_true(
    root.contains(
      "<div class=\"version-banner\"><p>Pre-release docs. No version is released yet. These pages show <code>main</code>.</p></div>",
    ),
  )
  assert_false(root.contains("rel=\"canonical\""))
  let next = @fs.read_file("\{dir}/next/docs/index.html").text()
  assert_true(next.contains("Pre-release docs."))
  assert_true(next.contains("href=\"/m/next/docs/\""))
  assert_false(@fs.exists("\{dir}/latest"))
  assert_eq(
    @fs.read_file("\{dir}/versions.json").text(),
    "{ \"latest\": null, \"next\": true, \"versions\": [] }\n",
  )
}

///|
async test "Old version page and Page in latest" {
  let dir = test_dir("two-trees")
  write_tree(dir, "next/", ["", "docs/design/overview/"])
  write_tree(dir, "v/0.2/", ["", "docs/design/overview/"])
  write_tree(dir, "v/0.1/", ["", "docs/design/overview/", "docs/old/"])
  assemble_site(dir, {
    base: "/m/",
    site_url: "https://e.org/m/",
    lines: ["0.2", "0.1"],
  })
  let old = @fs.read_file("\{dir}/v/0.1/docs/design/overview/index.html").text()
  assert_true(
    old.contains(
      "<p>You are reading 0.1 docs. The latest is 0.2. <a href=\"/m/latest/docs/design/overview/\">Open the latest docs</a>.</p>",
    ),
  )
  assert_true(
    old.contains(
      "<link rel=\"canonical\" href=\"https://e.org/m/latest/docs/design/overview/\"></head>",
    ),
  )
  let gone = @fs.read_file("\{dir}/v/0.1/docs/old/index.html").text()
  assert_true(gone.contains("<a href=\"/m/latest/\">Open the latest docs</a>"))
  assert_false(gone.contains("rel=\"canonical\""))
  let newest = @fs.read_file("\{dir}/v/0.2/index.html").text()
  assert_true(newest.contains("<div class=\"version-banner\"></div>"))
  assert_true(newest.contains("href=\"https://e.org/m/latest/\""))
  let latest = @fs.read_file("\{dir}/latest/docs/design/overview/index.html").text()
  assert_true(latest.contains("data-base=\"/m/latest/\""))
  assert_true(latest.contains("href=\"/m/latest/docs/design/overview/\""))
  assert_false(latest.contains("rel=\"canonical\""))
  let root = @fs.read_file("\{dir}/docs/design/overview/index.html").text()
  assert_true(root.contains("data-base=\"/m/\""))
  assert_true(root.contains("<div class=\"version-banner\"></div>"))
  assert_true(
    root.contains(
      "<link rel=\"canonical\" href=\"https://e.org/m/latest/docs/design/overview/\">",
    ),
  )
  let next = @fs.read_file("\{dir}/next/index.html").text()
  assert_true(
    next.contains(
      "<p>You are reading docs for <code>main</code>, which is not released. The latest is 0.2.</p>",
    ),
  )
  assert_eq(
    @fs.read_file("\{dir}/versions.json").text(),
    "{ \"latest\": \"0.2\", \"next\": true, \"versions\": [\"0.2\", \"0.1\"] }\n",
  )
}
