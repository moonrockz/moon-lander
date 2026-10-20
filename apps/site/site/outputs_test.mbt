///|
async test "build writes every route, feed, index and copies" {
  let built = @site.build(
    { ..config, packages: [], },
    [
      {
        path: "docs/ARCHITECTURE.md",
        text: Some("# Architecture\n\n![flow](images/flow.png)\n"),
      },
      { path: "docs/images/flow.png", text: None, },
      {
        path: "site/articles/2026-10-13-hello.md",
        text: Some(
          "---\ntitle: Hello\ndate: 2026-10-13\nauthors: [Ada]\n---\nHi.\n",
        ),
      },
      {
        path: "site/pages/index.html",
        text: Some(
          "<section class=\"hero\">Hero</section><div data-site=\"latest-articles\"></div>",
        ),
      },
    ],
    main_build=true,
  )
  let paths = built.outputs.map(o => {
    match o {
      Text(path, _) => path
      Copy(path, _) => path
    }
  })
  assert_eq(paths, [
    "docs/architecture/index.html", "articles/hello/index.html", "index.html", "docs/index.html",
    "articles/index.html", "articles/atom.xml", "search-index.json", "docs/architecture/images/flow.png",
  ])
  guard built.outputs[2] is Text(_, home) else { fail("home is not text") }
  assert_true(home.contains("Hero"))
  assert_true(home.contains("href=\"/m/articles/hello/\""))
  guard built.outputs[4] is Text(_, articles) else { fail("articles is not text") }
  assert_true(articles.contains("content=\"Articles about T\""))
}
