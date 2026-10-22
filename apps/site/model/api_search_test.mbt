///|
test "API item result" {
  let api = @model.ApiPackage::parse("package_data.json", notebooks_package_data)
  let entries = [
    @model.SearchEntry::{
      route: "/docs/WRITING_FOR_THE_SITE/",
      title: "Writing for the site",
      section: "Docs",
      summary: "How to write a page.",
      headings: ["API links"],
      text: "This link goes to CellKind.",
    },
  ] +
    @model.api_search_entries(api, entry => entry.docstring)
  let found = @model.search(entries, "CellKind")
  @expect.expect(@model.result_url("/moon-lander/", found[0])).to_equal(
    "/moon-lander/api/moonrockz/notebooks/#CellKind",
  )
}

///|
test "an API search entry has the name, the package and the first sentence" {
  let api = @model.ApiPackage::parse("package_data.json", notebooks_package_data)
  let entries = @model.api_search_entries(api, entry => entry.docstring)
  guard entries.search_by(e => e.route == "/api/moonrockz/notebooks/#CellKind")
    is Some(i) else {
    fail("no CellKind entry")
  }
  @expect.expect(entries[i]).to_equal({
    route: "/api/moonrockz/notebooks/#CellKind",
    title: "CellKind",
    section: "API",
    summary: "The common role of a cell, independent of its file format.",
    headings: ["moonrockz/notebooks"],
    text: "moonrockz/notebooks The common role of a cell, independent of its file format.",
  })
  @expect.expect(
    entries.iter().any(e => e.route == "/api/moonrockz/notebooks/#CellKind.equal" &&
      e.title == "CellKind::equal"),
  ).to_be_true()
  @expect.expect(
    entries.iter().any(e => e.route == "/api/moonrockz/notebooks/#Metadata.Eq.equal"),
  ).to_be_true()
}

///|
test "first sentence" {
  @expect.expect(@model.first_sentence(" Resolve a path.\n Return None.")).to_equal(
    "Resolve a path.",
  )
  @expect.expect(@model.first_sentence("Use v1.2 here. Then stop.")).to_equal(
    "Use v1.2 here.",
  )
  @expect.expect(@model.first_sentence("No stop")).to_equal("No stop")
  @expect.expect(@model.first_sentence("")).to_equal("")
}
