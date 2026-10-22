///|
fn newest_first(articles : Array[Page]) -> Array[Page] {
  let sorted = articles.copy()
  sorted.sort_by((a, b) => {
    if a.date != b.date {
      b.date.compare(a.date)
    } else {
      a.route.compare(b.route)
    }
  })
  sorted
}

///|
/// An Atom 1.0 feed of the newest 20 articles with their full HTML content.
pub fn atom_feed(config : @model.SiteConfig, articles : Array[Page]) -> String {
  let esc = @content.escape
  let sorted = newest_first(articles)
  let updated = if sorted.is_empty() {
    "1970-01-01T00:00:00Z"
  } else {
    "\{sorted[0].date}T00:00:00Z"
  }
  let out = StringBuilder()
  out.write_string("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
  out.write_string("<feed xmlns=\"http://www.w3.org/2005/Atom\">\n")
  out.write_string("<title>\{esc(config.title)} articles</title>\n")
  out.write_string("<id>\{esc(config.absolute("/articles/"))}</id>\n")
  out.write_string(
    "<link rel=\"self\" href=\"\{esc(config.absolute("/articles/atom.xml"))}\"/>\n",
  )
  out.write_string("<link href=\"\{esc(config.absolute("/articles/"))}\"/>\n")
  out.write_string("<updated>\{updated}</updated>\n")
  for article in sorted.iter().take(20) {
    let url = esc(config.absolute(article.route))
    out.write_string("<entry>\n")
    out.write_string("<title>\{esc(article.title)}</title>\n")
    out.write_string("<id>\{url}</id>\n")
    out.write_string("<link href=\"\{url}\"/>\n")
    out.write_string("<updated>\{article.date}T00:00:00Z</updated>\n")
    for author in article.authors {
      out.write_string("<author><name>\{esc(author)}</name></author>\n")
    }
    out.write_string("<summary>\{esc(article.summary)}</summary>\n")
    out.write_string("<content type=\"html\">\{esc(article.html)}</content>\n")
    out.write_string("</entry>\n")
  }
  out.write_string("</feed>\n")
  out.to_string()
}

///|
fn first_chars(text : String, limit : Int32) -> String {
  let out = StringBuilder()
  let mut n = 0
  for c in text {
    if n == limit {
      break
    }
    out.write_char(c)
    n += 1
  }
  out.to_string()
}

///|
/// The JSON search index of every page except full HTML pages and the landing page, then the
/// entries of `api`.
pub fn search_index(
  pages : Array[Page],
  api~ : Array[@model.SearchEntry] = [],
) -> String {
  let entries = pages
    .filter(p => !p.full && p.route != "/")
    .map(p => {
      let section = if p.kind is Article(_) { "Articles" } else { "Docs" }
      @model.SearchEntry::{
        route: p.route,
        title: p.title,
        section,
        summary: p.summary,
        headings: p.headings,
        text: first_chars(p.text, 2000),
      }.to_json()
    })
  Json::array(entries + api.map(e => e.to_json())).stringify()
}
