///|
pub(all) enum Output {
  /// `Text(out_path, content)`.
  Text(String, String)
  /// `Copy(out_path, repo_path)`.
  Copy(String, String)
}

///|
pub(all) struct Built {
  outputs : Array[Output]
  warnings : Array[@model.Problem]
}

///|
fn meta(
  config : @model.SiteConfig,
  route : String,
  title : String,
  description : String,
  section : @model.Section,
) -> @views.PageMeta {
  { config, route, title, description, section }
}

///|
/// Prepare, then render every page, the docs index, the articles index, the feed, the
/// search index and the API pages of `api`. Outputs keep source order, then generated
/// files, then copies.
pub async fn build(
  config : @model.SiteConfig,
  sources : Array[SourceFile],
  main_build~ : Bool,
  api~ : ApiSite = no_api,
) -> Built {
  let prepared = prepare(config, sources, main_build~, api~)
  let pages = prepared.pages
  let entries = nav_entries(pages)
  let nav = match config.nav {
    None => build_nav(entries)
    Some(groups) => build_grouped_nav(groups, entries).0
  }
  let articles = newest_first(pages.filter(p => p.kind is Article(_)))
  let summaries = articles.map(p => @model.ArticleSummary::{
    route: p.route,
    title: p.title,
    date: p.date,
    authors: p.authors,
    summary: p.summary,
  })
  let outputs : Array[Output] = []
  for page in pages {
    if page.full {
      outputs.push(Text(@model.route_file(page.route), page.html))
      continue
    }
    let html = match page.kind {
      Article(_) => {
        let m = meta(
          config,
          page.route,
          page.title,
          page.summary,
          Articles
        )
        let summary = summaries[summaries
          .search_by(s => s.route == page.route)
          .unwrap()]
        @views.render(m, @views.article_page(m, summary, page.html))
      }
      Landing => {
        let m = meta(
          config,
          "/",
          config.title,
          config.description,
          Home
        )
        @views.render(
          m,
          @views.home_page(m, page.html, summaries.iter().take(3).collect()),
        )
      }
      _ => {
        let m = meta(
          config,
          page.route,
          page.title,
          page.summary,
          Docs
        )
        let source = "\{config.repo_url}/blob/main/\{page.source}"
        @views.render(
          m,
          @views.docs_page(
            m,
            nav,
            page.html,
            Some(source),
            toc=page.toc,
            proposed=page.proposed,
          ),
        )
      }
    }
    outputs.push(Text(@model.route_file(page.route), html))
  }
  if !pages.iter().any(p => p.route == "/docs/") {
    let m = meta(
      config,
      "/docs/",
      "Documentation",
      config.description,
      Docs,
    )
    let body = "<h1 id=\"documentation\">Documentation</h1><p>Choose a page from the list.</p>"
    outputs.push(
      Text(
        "docs/index.html",
        @views.render(m, @views.docs_page(m, nav, body, None)),
      ),
    )
  }
  let index = meta(
    config,
    "/articles/",
    "Articles",
    "Articles about \{config.title}",
    Articles,
  )
  outputs.push(
    Text(
      "articles/index.html",
      @views.render(index, @views.articles_index(index, summaries)),
    ),
  )
  outputs.push(Text("articles/atom.xml", atom_feed(config, articles)))
  outputs.push(Text("search-index.json", search_index(pages)))
  outputs.append(api_outputs(config, api))
  for copy in prepared.copies {
    outputs.push(Copy(copy.0, copy.1))
  }
  { outputs, warnings: prepared.warnings, }
}
