///|
fn entry(
  route : String,
  title : String,
  headings : Array[String],
  text : String,
) -> @model.SearchEntry {
  { route, title, section: "Docs", summary: "", headings, text, }
}

///|
let entries : Array[@model.SearchEntry] = [
  entry("/docs/a/", "Architecture", ["Packages"], "the scheme engine"),
  entry("/docs/b/", "Quick start", ["Architecture notes"], "install mise"),
  entry("/docs/c/", "Tasks", [], "architecture of tasks and adr records"),
]

///|
test "title beats heading beats text" {
  assert_eq(@model.search(entries, "arch").map(e => e.route), [
    "/docs/a/", "/docs/b/", "/docs/c/",
  ])
}

///|
test "all tokens must match, case-insensitive prefixes" {
  assert_eq(@model.search(entries, "ARCH ADR").map(e => e.route), ["/docs/c/"])
  assert_eq(@model.search(entries, "zzz"), [])
}

///|
test "blank query and limit" {
  assert_eq(@model.search(entries, "   "), [])
  assert_eq(@model.search(entries, "arch", limit=1).length(), 1)
}

///|
test "search entry json round trip" {
  let e = entries[0]
  assert_eq(@model.SearchEntry::from_json(e.to_json()), Some(e))
  assert_eq(@model.SearchEntry::from_json(Json::null()), None)
}

///|
test "arrow keys move the selection and stay in the list" {
  assert_eq(@model.move_selection(0, 3, "ArrowDown"), 1)
  assert_eq(@model.move_selection(2, 3, "ArrowDown"), 2)
  assert_eq(@model.move_selection(0, 3, "ArrowUp"), 0)
  assert_eq(@model.move_selection(2, 3, "ArrowUp"), 1)
  assert_eq(@model.move_selection(0, 0, "ArrowDown"), 0)
  assert_eq(@model.move_selection(1, 3, "a"), 1)
}

///|
test "No match" {
  assert_eq(@model.search(entries, "zzzqqq"), [])
}

///|
test "Search result opens the first result below the base path" {
  let found = @model.search(entries, "arch")
  assert_eq(@model.result_url("/moon-lander/", found[0]), "/moon-lander/docs/a/")
}

///|
test "a result route can end with an anchor" {
  let item = entry("/api/moonrockz/notebooks/#CellKind", "CellKind", [], "")
  assert_eq(
    @model.result_url("/moon-lander/", item),
    "/moon-lander/api/moonrockz/notebooks/#CellKind",
  )
}

///|
test "search entry from the fields of the island" {
  assert_eq(
    @model.SearchEntry::from_fields([
      "/docs/a/", "A", "Docs", "s", "t", "H1", "H2",
    ]),
    Some({
      route: "/docs/a/",
      title: "A",
      section: "Docs",
      summary: "s",
      text: "t",
      headings: ["H1", "H2"],
    }),
  )
  assert_eq(
    @model.SearchEntry::from_fields(["/docs/a/", "A", "Docs", "s"]),
    None,
  )
}
