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
test "a title tag matches in any case and can have attributes" {
  @expect.expect(@model.has_title("<TITLE>Page</TITLE>")).to_equal(true)
  @expect.expect(@model.has_title("<title lang=\"en\">Page</title>")).to_equal(
    true,
  )
  @expect.expect(@model.has_title("<titles>Page</titles>")).to_equal(false)
}

///|
test "a title in a comment, a script or a style does not count" {
  @expect.expect(@model.has_title("<!-- <title>Page</title> -->")).to_equal(
    false,
  )
  @expect.expect(
    @model.has_title("<script>let t = \"<title>Page</title>\"</script>"),
  ).to_equal(false)
  @expect.expect(
    @model.has_title("<STYLE>/* <title>x</title> */</STYLE><title>Real</title>"),
  ).to_equal(true)
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

///|
test "a feed with balanced tags can still be malformed" {
  let problem = (xml : String) => @model.xml_problem(xml)
  @expect.expect(problem("<feed><title>A & B</title></feed>")).to_equal(
    Some("`&` does not start an entity or character reference"),
  )
  @expect.expect(problem("<feed><title>A &nbsp; B</title></feed>")).to_equal(
    Some("`&` does not start an entity or character reference"),
  )
  @expect.expect(problem("<feed></feed><feed></feed>")).to_equal(
    Some("`<feed>` is a second root element"),
  )
  @expect.expect(problem("<feed></feed>x")).to_equal(
    Some("text is outside the root element"),
  )
  @expect.expect(problem("<feed a=\"1\" a=\"2\"></feed>")).to_equal(
    Some("`<feed>` has the attribute `a` twice"),
  )
  @expect.expect(problem("<feed a=1></feed>")).to_equal(
    Some("the value of `a` in `<feed>` is not quoted"),
  )
  @expect.expect(problem("<1feed></1feed>")).to_equal(
    Some("a start tag has no valid name"),
  )
  @expect.expect(problem("<?xml version=\"1.0\"?>")).to_equal(
    Some("there is no root element"),
  )
}

///|
test "entities, CDATA and empty elements are well-formed" {
  @expect.expect(
    @model.xml_problem(
      "<feed><title type=\"html\">A &amp; B &#38; &#x26;</title><link href=\"x?a=1&amp;b=2\"/><content><![CDATA[a < b & c]]></content></feed>",
    ),
  ).to_equal(None)
}
