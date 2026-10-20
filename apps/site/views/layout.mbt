///|
using @html {type Html}

///|
/// What the layout needs to know about one page.
pub(all) struct PageMeta {
  config : @model.SiteConfig
  route : String
  /// The page title. An empty title shows the site title only.
  title : String
  description : String
}

///|
/// A block of reviewed HTML, such as the landing page source.
pub fn raw(html : String, class~ : String = "prose") -> Html {
  @html.div(class~, attrs=@html.Attrs::build().inner_html(html), @html.nothing)
}

///|
/// The page frame: head, header, main content and footer. Every link starts with the base path.
pub fn layout(meta : PageMeta, main : Html) -> Html {
  let config = meta.config
  let title = if meta.title == "" {
    config.title
  } else {
    "\{meta.title} · \{config.title}"
  }
  @html.html(
    lang="en",
    attrs=@html.Attrs::build().data_set("base", config.base_path),
    [
      @html.head([
        @html.meta(charset="utf-8"),
        @html.meta(name="viewport", content="width=device-width, initial-scale=1"),
        @html.title(title),
        @html.meta(name="description", content=meta.description),
        @html.link(rel="stylesheet", href=config.href("/assets/site.css")),
      ]),
      @html.body([
        @html.a(href="#content", class="skip-link", "Skip to content"),
        @html.header(class="site-header", [
          @html.a(href=config.href("/"), class="brand", config.title),
          @html.nav(
            class="site-links",
            attrs=@html.Attrs::build().aria_label("Main"),
            [@html.a(href=config.repo_url, "GitHub")],
          ),
        ]),
        @html.main_(id="content", [main]),
        @html.footer(class="site-footer", [
          @html.p("Apache-2.0 · Moon-Lander, an application framework for MoonBit"),
        ]),
      ]),
    ],
  )
}

///|
/// The page as an HTML document.
pub async fn render(meta : PageMeta, main : Html) -> String {
  let page = layout(meta, main)
  @rabbita.new(() => @rabbita.Val::constant(page)).render(
    url=meta.config.absolute(meta.route),
  )
}
