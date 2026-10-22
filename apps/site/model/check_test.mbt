///|
test "internal links are the href and src values that start with /" {
  @expect.expect(
    @model.internal_links(
      "<link href=\"/b/assets/site.css\"><a href=\"https://e.org/\">x</a><a href=\"//cdn/x\">y</a><a href=\"#top\">t</a><img src=\"/b/i.svg\"><a href=\"/b/docs/#install\">d</a>",
    ),
  ).to_equal(["/b/assets/site.css", "/b/i.svg", "/b/docs/#install"])
}

///|
test "internal links accept any valid quoting, spacing and case" {
  @expect.expect(
    @model.internal_links(
      "<a href='/b/one/'>1</a><a HREF = \"/b/two/\">2</a><a href=/b/three/>3</a><img\nsrc=/b/four.svg alt=x>",
    ),
  ).to_equal(["/b/one/", "/b/two/", "/b/three/", "/b/four.svg"])
}

///|
test "a name that only ends with href is not an attribute" {
  @expect.expect(
    @model.internal_links("<a data-href=\"/b/x/\" data-src=\"/b/y\">x</a>"),
  ).to_equal([])
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

///|
test "a link with a dot segment leaves the base path" {
  @expect.expect(@model.link_file("/b/", "/b/../README.md")).to_equal(None)
  @expect.expect(@model.link_file("/b/", "/b/docs/./x/")).to_equal(None)
}

///|
test "a page title must have text" {
  @expect.expect(@model.has_title("<head><title>A · B</title></head>")).to_equal(
    true,
  )
  @expect.expect(@model.has_title("<title> \n </title>")).to_equal(false)
  @expect.expect(@model.has_title("<title>A")).to_equal(false)
  @expect.expect(@model.has_title("<h1>A</h1>")).to_equal(false)
}

///|
test "a well-formed feed has balanced tags" {
  let feed =
    #|<?xml version="1.0" encoding="utf-8"?>
    #|<feed xmlns="http://www.w3.org/2005/Atom"><title>T</title>
    #|<link href="https://x.io/" rel="alternate"/><!-- note -->
    #|<entry><title>A</title></entry></feed>
  @expect.expect(@model.xml_problem(feed)).to_equal(None)
}

///|
test "a feed with unbalanced tags names the first problem" {
  @expect.expect(@model.xml_problem("<feed><entry></feed>")).to_equal(
    Some("`</feed>` closes `<entry>`"),
  )
  @expect.expect(@model.xml_problem("<feed><entry></entry>")).to_equal(
    Some("`<feed>` is not closed"),
  )
  @expect.expect(@model.xml_problem("</feed>")).to_equal(
    Some("`</feed>` has no start tag"),
  )
  @expect.expect(@model.xml_problem("<feed")).to_equal(Some("`<` has no `>`"))
}
