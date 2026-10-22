///|
/// The scenarios of `openspec/changes/add-docs-site/specs/docs-site/spec.md` that `prepare` decides.
let lander : @model.SiteConfig = {
  title: "Moon-Lander",
  description: "An application framework for MoonBit.",
  base_path: "/moon-lander/",
  site_url: "https://moonrockz.github.io/moon-lander/",
  repo_url: "https://github.com/moonrockz/moon-lander",
  packages: [],
  api: [],
  nav: None,
  chapters: [],
}

///|
fn source(path : String, body : String) -> @site.SourceFile {
  { path, text: Some(body) }
}

///|
fn scenario_problems(
  sources : Array[@site.SourceFile],
  config~ : @model.SiteConfig = lander,
  main_build~ : Bool = false,
) -> Array[String] {
  try @site.prepare(config, sources, main_build~) catch {
    @model.Invalid(problems) => problems.map(p => p.render())
  } noraise {
    _ => []
  }
}

///|
fn page(
  prepared : @site.Prepared,
  route : String,
) -> @site.Page raise Failure {
  match prepared.pages.search_by(p => p.route == route) {
    Some(i) => prepared.pages[i]
    None => fail("no page at \{route}")
  }
}

///|
test "Plan not excluded" {
  assert_eq(
    scenario_problems([source("docs/superpowers/plans/p.md", "# Plan\n")]),
    [
      "docs/superpowers/plans/p.md: forbidden path: agent specs, plans and ledgers live in beads",
    ],
  )
}

///|
test "New page not in nav" {
  let config = {
    ..lander,
    nav: Some([{ group: "Design", items: ["design/"] }]),
  }
  let problems = scenario_problems(
    [
      source("docs/design/overview.md", "# Overview\n"),
      source("docs/NEW_PAGE.md", "# New\n"),
    ],
    config~,
  )
  assert_eq(problems.length(), 1)
  assert_true(problems[0].contains("NEW_PAGE.md"), msg=problems[0])
}

///|
test "Draft in a local build" {
  let prepared = @site.prepare(
    lander,
    [source("docs/a.md", "---\ndraft: true\n---\n# A\n")],
    main_build=false,
  )
  assert_eq(prepared.pages.length(), 0)
  assert_eq(prepared.warnings.map(w => w.render()), [
    "docs/a.md: draft page skipped",
  ])
}

///|
test "Draft in a main build" {
  assert_eq(
    scenario_problems(
      [source("docs/a.md", "---\ndraft: true\n---\n# A\n")],
      main_build=true,
    ),
    ["docs/a.md: draft page in a main build"],
  )
}

///|
test "Package page" {
  let prepared = @site.prepare(
    { ..lander, packages: ["notebooks"] },
    [source("pkgs/notebooks/README.md", "# Notebooks\n\nModels.\n")],
    main_build=true,
  )
  let p = page(prepared, "/docs/packages/notebooks/")
  assert_eq(p.source, "pkgs/notebooks/README.md")
  assert_eq(p.title, "Notebooks")
}

///|
test "Two README kinds in one directory" {
  let problems = scenario_problems(
    [
      source("pkgs/notebooks/README.md", "# A\n"),
      source("pkgs/notebooks/README.mbt.md", "# B\n"),
    ],
    config={ ..lander, packages: ["notebooks"] },
  )
  assert_eq(problems, [
    "pkgs/notebooks/README.md: pkgs/notebooks has both README.md and README.mbt.md",
  ])
}

///|
test "Relative Markdown link" {
  let prepared = @site.prepare(
    lander,
    [
      source(
        "docs/WRITING_FOR_THE_SITE.md", "# Writing\n\nSee [layers](design/overview.md#the-layer-stack).\n",
      ),
      source("docs/design/overview.md", "# Overview\n\n## The layer stack\n"),
    ],
    main_build=true,
  )
  assert_true(
    page(prepared, "/docs/writing_for_the_site/").html.contains(
      "href=\"/moon-lander/docs/design/overview/#the-layer-stack\"",
    ),
  )
}

///|
test "Missing anchor" {
  assert_eq(
    scenario_problems([
      source("docs/a.md", "# A\n\n[x](design/overview.md#no-such-heading)\n"),
      source("docs/design/overview.md", "# Overview\n"),
    ]),
    [
      "docs/a.md: anchor `#no-such-heading` does not exist on `/docs/design/overview/`",
    ],
  )
}

///|
test "SVG figure" {
  let prepared = @site.prepare(
    lander,
    [
      source(
        "docs/design/overview.md", "# Overview\n\n![Run order](images/run-order.svg)\n",
      ),
      { path: "docs/design/images/run-order.svg", text: None },
    ],
    main_build=true,
  )
  assert_eq(prepared.copies, [
    ("docs/design/overview/images/run-order.svg", "docs/design/images/run-order.svg"),
  ])
  assert_true(
    page(prepared, "/docs/design/overview/").html.contains(
      "src=\"/moon-lander/docs/design/overview/images/run-order.svg\"",
    ),
  )
  assert_eq(
    scenario_problems([
      source("docs/design/overview.md", "# Overview\n\n![x](images/missing.svg)\n"),
    ]),
    [
      "docs/design/overview.md: broken link `images/missing.svg`: `docs/design/images/missing.svg` does not exist",
    ],
  )
}

///|
test "Article route" {
  let prepared = @site.prepare(
    lander,
    [
      source(
        "site/articles/2026-11-02-first-host.md", "---\ntitle: First host\ndate: 2026-11-02\nauthors: [Moon-Lander team]\n---\nHello.\n",
      ),
    ],
    main_build=true,
  )
  assert_eq(page(prepared, "/articles/first-host/").date, "2026-11-02")
  let feed = @site.atom_feed(lander, prepared.pages)
  assert_true(
    feed.contains(
      "<id>https://moonrockz.github.io/moon-lander/articles/first-host/</id>",
    ),
  )
}

///|
test "Date does not match" {
  let problems = scenario_problems([
    source(
      "site/articles/2026-11-02-first-host.md", "---\ntitle: T\ndate: 2026-11-03\nauthors: [A]\n---\nx\n",
    ),
  ])
  assert_eq(problems, [
    "site/articles/2026-11-02-first-host.md: `date` 2026-11-03 does not match the file name date 2026-11-02",
  ])
}

///|
test "Date is not real" {
  let problems = scenario_problems([
    source(
      "site/articles/2026-02-30-x.md", "---\ntitle: T\ndate: 2026-02-30\nauthors: [A]\n---\nx\n",
    ),
  ])
  assert_eq(problems.length(), 1)
  assert_true(
    problems[0].has_prefix("site/articles/2026-02-30-x.md: "),
    msg=problems[0],
  )
}

///|
test "Tables render as HTML tables" {
  let prepared = @site.prepare(
    lander,
    [source("docs/a.md", "# A\n\n| Code | Meaning |\n| --- | --- |\n| 0 | Success |\n")],
    main_build=true,
  )
  let html = page(prepared, "/docs/a/").html
  assert_true(html.contains("<table>"), msg=html)
  assert_true(html.contains("<td>Success</td>"), msg=html)
}

///|
test "Diagram renders" {
  let prepared = @site.prepare(
    lander,
    [source("docs/a.md", "# A\n\n```mermaid\ngraph LR\nA --> B\n```\n")],
    main_build=true,
  )
  let html = page(prepared, "/docs/a/").html
  assert_true(html.contains("<figure class=\"diagram\"><svg"))
  assert_false(html.contains("mermaid"))
}

///|
test "Diagram does not render" {
  let problems = scenario_problems([
    source("docs/a.md", "# A\n\n```mermaid\ngantt\ntitle x\n```\n"),
  ])
  assert_eq(problems.length(), 1)
  assert_true(
    problems[0].has_prefix("docs/a.md: Mermaid diagram 1 does not render"),
    msg=problems[0],
  )
}

///|
test "Warning callout" {
  let prepared = @site.prepare(
    lander,
    [source("docs/a.md", "# A\n\n> [!WARNING]\n> Stop first.\n")],
    main_build=true,
  )
  assert_true(
    page(prepared, "/docs/a/").html.contains(
      "<aside class=\"callout warning\"><p class=\"callout-label\">Warning</p>",
    ),
  )
}

///|
test "Layer stack" {
  let prepared = @site.prepare(
    lander,
    [
      source(
        "docs/a.md", "# A\n\n```layers\nOverrides | --set key=value\nDefaults | code\n```\n",
      ),
    ],
    main_build=true,
  )
  let html = page(prepared, "/docs/a/").html
  let first = html.find("Overrides").unwrap()
  let second = html.find("Defaults").unwrap()
  assert_true(html.contains("<figure class=\"layer-stack\"><ol>"))
  assert_true(first < second)
}

///|
test "Bad layer line" {
  assert_eq(
    scenario_problems([source("docs/a.md", "# A\n\n```layers\nOverrides\n```\n")]),
    [
      "docs/a.md: layers block 1: line `Overrides` must have the form `name | detail`",
    ],
  )
}

///|
test "Proposed page" {
  let prepared = @site.prepare(
    lander,
    [source("docs/a.md", "---\nstatus: proposed\n---\n# A\n")],
    main_build=true,
  )
  assert_true(page(prepared, "/docs/a/").proposed)
}

///|
test "Unknown status" {
  assert_eq(
    scenario_problems([source("docs/a.md", "---\nstatus: draft-ish\n---\n# A\n")]),
    [
      "docs/a.md: unknown `status` value `draft-ish`: the only value is `proposed`",
    ],
  )
}

///|
test "Untested example in docs" {
  assert_eq(
    scenario_problems([
      source("docs/a.md", "---\ntitle: A\n---\n# A\n\n```moonbit\nlet x = 1\n```\n"),
    ]),
    [
      "docs/a.md:6: a `moonbit` fence outside a `.mbt.md` file is not compiled: write ```moonbit notest, or move the example to a tested `.mbt.md` file",
    ],
  )
}

///|
test "Example of a proposed API" {
  let prepared = @site.prepare(
    lander,
    [source("docs/a.md", "# A\n\n```moonbit notest\nlet x = 1\n```\n")],
    main_build=true,
  )
  assert_true(
    page(prepared, "/docs/a/").html.contains(
      "<pre><code class=\"language-moonbit\">",
    ),
  )
}

///|
test "Tested example" {
  let prepared = @site.prepare(
    { ..lander, packages: ["notebooks"] },
    [
      source(
        "pkgs/notebooks/README.mbt.md", "# Notebooks\n\n```mbt check\ntest { inspect(1) }\n```\n",
      ),
    ],
    main_build=true,
  )
  assert_true(
    page(prepared, "/docs/packages/notebooks/").html.contains(
      "<pre><code class=\"language-mbt\">",
    ),
  )
}
