///|
/// A fixture for the link guard of the islands. It is not a package, so moon does not build it.
fn result_link(base : String) -> @html.Html {
  @html.li([
    @html.a(href=base + "docs/", "Docs"),
    @html.a(href=base + "articles/", "Articles", escape=true),
  ])
}
