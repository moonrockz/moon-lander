///|
pub let latest_articles_marker : String = "<div data-site=\"latest-articles\"></div>"

///|
fn nav_entry(meta : PageMeta, item : @model.NavItem) -> Html {
  let class = "depth-\{item.depth}"
  if item.route == "" {
    @html.li(class~, [@html.span(class="nav-label", item.title)])
  } else if item.route == meta.route {
    @html.li(class~, [
      @html.a(
        href=meta.config.href(item.route),
        class="current",
        attrs=@html.Attrs::build().aria_current("page"),
        nav_text(item),
      ),
    ])
  } else {
    @html.li(class~, [
      @html.a(href=meta.config.href(item.route), nav_text(item)),
    ])
  }
}

///|
/// The sidebar link of a page, with the "Proposed" badge for a page with `status: proposed`.
fn nav_text(item : @model.NavItem) -> Array[Html] {
  if item.proposed {
    [@html.text(item.title + " "), @html.span(class="badge", "Proposed")]
  } else {
    [@html.text(item.title)]
  }
}

///|
pub fn docs_page(
  meta : PageMeta,
  nav : Array[@model.NavItem],
  body : String,
  source_url : String?,
  toc~ : Array[@model.TocEntry] = [],
  proposed~ : Bool = false,
) -> Html {
  let banner = if proposed {
    [
      @html.p(
        class="status-banner",
        attrs=@html.Attrs::build().role("note"),
        "Proposed — not implemented",
      ),
    ]
  } else {
    []
  }
  let source = match source_url {
    Some(url) =>
      [
        @html.p(class="page-source", [
          @html.a(href=url, "View source on GitHub"),
        ]),
      ]
    None => []
  }
  let rail = if toc.is_empty() {
    []
  } else {
    [
      @html.aside(class="docs-rail", [
        @html.nav(
          id="site-toc",
          class="docs-toc",
          attrs=@html.Attrs::build().aria_label("On this page"),
          [
            @html.p(class="nav-label", "On this page"),
            @html.ul(
              toc.map(e => {
                @html.li(class="depth-\{e.depth}", [
                  @html.a(href="#\{e.id}", e.text),
                ])
              }),
            ),
          ],
        ),
      ]),
    ]
  }
  @html.div(
    class="docs-layout",
    [
      @html.aside(class="docs-sidebar", [
        @html.nav(attrs=@html.Attrs::build().aria_label("Documentation"), [
          @html.ul(nav.map(item => nav_entry(meta, item))),
        ]),
      ]),
      @html.article(class="docs-article", banner + [raw(body)] + source),
    ] +
    rail,
  )
}

///|
fn byline(article : @model.ArticleSummary) -> Html {
  @html.p(class="article-meta", [
    @html.time(datetime=article.date, article.date),
    @html.text(" · " + article.authors.join(", ")),
  ])
}

///|
pub fn article_page(
  meta : PageMeta,
  article : @model.ArticleSummary,
  body : String,
) -> Html {
  ignore(meta)
  @html.article(class="article", [
    @html.header([@html.h1(article.title), byline(article)]),
    raw(body),
  ])
}

///|
fn article_card(meta : PageMeta, article : @model.ArticleSummary) -> Html {
  @html.li(class="article-card", [
    @html.a(href=meta.config.href(article.route), article.title),
    byline(article),
    @html.p(article.summary),
  ])
}

///|
pub fn articles_index(meta : PageMeta, articles : Array[@model.ArticleSummary]) -> Html {
  @html.section(class="articles-index", [
    @html.h1("Articles"),
    @html.p([@html.a(href=meta.config.href("/articles/atom.xml"), "Atom feed")]),
    @html.ul(class="article-list", articles.map(p => article_card(meta, p))),
  ])
}

///|
/// The landing page. `latest_articles_marker` must be at the top level of `landing`;
/// the newest articles replace it.
pub fn home_page(
  meta : PageMeta,
  landing : String,
  latest : Array[@model.ArticleSummary],
) -> Html {
  let (before, after) = match landing.find(latest_articles_marker) {
    Some(i) =>
      (
        landing[:i].to_owned(),
        landing[i + latest_articles_marker.length():].to_owned(),
      )
    None => (landing, "")
  }
  let articles = if latest.is_empty() {
    []
  } else {
    [
      @html.section(class="latest-articles", [
        @html.h2("Latest articles"),
        @html.ul(class="article-list", latest.map(p => article_card(meta, p))),
      ]),
    ]
  }
  @html.div(
    class="home",
    [raw(before, class="landing")] + articles + [raw(after, class="landing")],
  )
}
