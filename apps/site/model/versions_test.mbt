///|
test "Reserved route" {
  assert_true(@model.reserved_route("/next/"))
  assert_true(@model.reserved_route("/v/0.1/docs/"))
  assert_true(@model.reserved_route("/latest"))
  assert_false(@model.reserved_route("/"))
  assert_false(@model.reserved_route("/docs/next/"))
  assert_false(@model.reserved_route("/nextgen/"))
}

///|
test "Minor line tree" {
  assert_eq(@model.tree_path("next"), "next/")
  assert_eq(@model.tree_path("0.1"), "v/0.1/")
  assert_true(@model.is_minor_line("0.1"))
  assert_true(@model.is_minor_line("12.30"))
  assert_false(@model.is_minor_line("0.1.3"))
  assert_false(@model.is_minor_line("next"))
  assert_false(@model.is_minor_line("0."))
}

///|
test "site root of a tree" {
  assert_eq(@model.site_root("/moon-lander/"), "/moon-lander/")
  assert_eq(@model.site_root("/moon-lander/next/"), "/moon-lander/")
  assert_eq(@model.site_root("/moon-lander/latest/"), "/moon-lander/")
  assert_eq(@model.site_root("/moon-lander/v/0.1/"), "/moon-lander/")
  assert_eq(@model.site_root("/"), "/")
  assert_eq(@model.site_root("/docs/0.1/"), "/docs/0.1/")
}

///|
test "Search in an old version" {
  assert_eq(
    @model.search_index_url("/moon-lander/v/0.1/"),
    "/moon-lander/v/0.1/search-index.json",
  )
}

///|
test "Page exists" {
  let base = "/moon-lander/v/0.2/"
  let target = @model.choice_base("/moon-lander/", "0.1")
  let path = "/moon-lander/v/0.2/docs/design/overview/"
  assert_eq(
    @model.switch_probe(path, base, target),
    "/moon-lander/v/0.1/docs/design/overview/",
  )
  assert_eq(
    @model.switch_url(path, base, target, true),
    "/moon-lander/v/0.1/docs/design/overview/",
  )
}

///|
test "Page missing" {
  let base = "/moon-lander/v/0.2/"
  let target = @model.choice_base("/moon-lander/", "0.1")
  assert_eq(
    @model.switch_url(
      "/moon-lander/v/0.2/api/moonrockz/moon-lander/config/",
      base,
      target,
      false,
    ),
    "/moon-lander/v/0.1/",
  )
  assert_eq(@model.choice_base("/moon-lander/", "latest"), "/moon-lander/latest/")
  assert_eq(@model.choice_base("/moon-lander/", "next"), "/moon-lander/next/")
}

///|
test "switcher choices and the current choice" {
  let file : @model.VersionsFile = {
    latest: Some("0.2"),
    next: true,
    versions: ["0.2", "0.1"],
  }
  assert_eq(file.choices(), ["latest", "next", "0.2", "0.1"])
  assert_eq(@model.choice_label("latest", Some("0.2")), "Latest (0.2)")
  assert_eq(@model.choice_label("next", Some("0.2")), "main")
  assert_eq(@model.choice_label("0.1", Some("0.2")), "0.1")
  assert_eq(@model.current_choice("/m/", "/m/v/0.1/", Some("0.2")), "0.1")
  assert_eq(@model.current_choice("/m/", "/m/latest/", Some("0.2")), "latest")
  assert_eq(@model.current_choice("/m/", "/m/next/", Some("0.2")), "next")
  assert_eq(@model.current_choice("/m/", "/m/", Some("0.2")), "latest")
  assert_eq(@model.current_choice("/m/", "/m/", None), "next")
  let early : @model.VersionsFile = { latest: None, next: true, versions: [] }
  assert_eq(early.choices(), ["next"])
}

///|
test "versions file round trip and trees" {
  let file : @model.VersionsFile = {
    latest: Some("0.2"),
    next: true,
    versions: ["0.2", "0.1"],
  }
  assert_eq(
    file.to_text(),
    "{ \"latest\": \"0.2\", \"next\": true, \"versions\": [\"0.2\", \"0.1\"] }\n",
  )
  assert_eq(@model.VersionsFile::parse("versions.json", file.to_text()), file)
  assert_eq(file.trees("/m/"), [
    ("", "/m/"),
    ("latest/", "/m/latest/"),
    ("next/", "/m/next/"),
    ("v/0.2/", "/m/v/0.2/"),
    ("v/0.1/", "/m/v/0.1/"),
  ])
  let none : @model.VersionsFile = { latest: None, next: true, versions: [] }
  assert_eq(@model.VersionsFile::parse("v.json", none.to_text()), none)
  assert_eq(none.trees("/m/"), [("", "/m/"), ("next/", "/m/next/")])
  let bad = try @model.VersionsFile::parse("v.json", "{\"latest\": 2}") catch {
    @model.Invalid(problems) => problems[0].render()
  } noraise {
    _ => ""
  }
  assert_eq(bad, "v.json: `latest` must be a minor line or null")
}

///|
test "the tree check reads a page without its banner" {
  let html = "<div class=\"version-banner\"><p>Old. <a href=\"/m/latest/\">Latest</a></p></div><a href=\"/m/v/0.1/x/\">x</a>"
  assert_eq(
    @model.without_banner(html),
    "<div class=\"version-banner\"></div><a href=\"/m/v/0.1/x/\">x</a>",
  )
  assert_eq(@model.without_banner("<p>no banner</p>"), "<p>no banner</p>")
}
