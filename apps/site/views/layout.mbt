///|
using @html {type Html}

///|
pub(all) struct PageMeta {
  config : @model.SiteConfig
  route : String
  title : String
  description : String
  section : @model.Section
}

///|
/// A block of reviewed HTML.
pub fn raw(html : String, class~ : String = "prose") -> Html {
  @html.div(class~, attrs=@html.Attrs::build().inner_html(html), @html.nothing)
}

///|
fn nav_link(
  meta : PageMeta,
  section : @model.Section,
  route : String,
  label : String,
) -> Html {
  if meta.section == section {
    @html.a(
      href=meta.config.href(route),
      class="current",
      attrs=@html.Attrs::build().aria_current("page"),
      label,
    )
  } else {
    @html.a(href=meta.config.href(route), label)
  }
}

///|
/// The page frame: head, header, main content and footer. Every link starts with the base path, and
/// the page works without JavaScript.
pub fn layout(meta : PageMeta, main : Html) -> Html {
  let config = meta.config
  let title = if meta.section == Home {
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
        @html.link(
          rel="alternate",
          type_="application/atom+xml",
          href=config.href("/articles/atom.xml"),
          title="\{config.title} articles",
        ),
      ]),
      @html.body([
        @html.a(href="#content", class="skip-link", "Skip to content"),
        @html.header(class="site-header", [
          @html.a(href=config.href("/"), class="brand", config.title),
          @html.nav(
            id="site-links",
            class="site-links",
            attrs=@html.Attrs::build().aria_label("Main"),
            [
              nav_link(meta, Docs, "/docs/", "Docs"),
              nav_link(meta, Articles, "/articles/", "Articles"),
              @html.a(href=config.repo_url, "GitHub"),
            ],
          ),
        ]),
        @html.main_(id="content", [main]),
        @html.footer(class="site-footer", [
          @html.p(
            "Apache-2.0 · Moon-Lander, an application framework for MoonBit",
          ),
        ]),
      ]),
    ],
  )
}

///|
pub async fn render(meta : PageMeta, main : Html) -> String {
  let page = layout(meta, main)
  @rabbita.new(() => @rabbita.Val::constant(page)).render(
    url=meta.config.absolute(meta.route),
  )
}
