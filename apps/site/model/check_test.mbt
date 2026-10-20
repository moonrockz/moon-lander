///|
test "internal links are the href and src values that start with /" {
  @expect.expect(
    @model.internal_links(
      "<link href=\"/b/assets/site.css\"><a href=\"https://e.org/\">x</a><a href=\"//cdn/x\">y</a><a href=\"#top\">t</a><img src=\"/b/i.svg\"><a href=\"/b/docs/#install\">d</a>",
    ),
  ).to_equal(["/b/assets/site.css", "/b/docs/#install", "/b/i.svg"])
}

///|
test "a link maps to the file that serves it" {
  @expect.expect(@model.link_file("/b/", "/b/")).to_equal(Some("index.html"))
  @expect.expect(@model.link_file("/b/", "/b/docs/?q=1#x")).to_equal(
    Some("docs/index.html"),
  )
  @expect.expect(@model.link_file("/b/", "/b/assets/site.css")).to_equal(
    Some("assets/site.css"),
  )
}

///|
test "a link outside the base path has no file" {
  @expect.expect(@model.link_file("/b/", "/other/")).to_equal(None)
  @expect.expect(@model.link_file("/b/", "/b")).to_equal(None)
}
