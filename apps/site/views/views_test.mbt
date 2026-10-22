///|
let config : @model.SiteConfig = {
  title: "Moon-Lander",
  description: "An application framework for MoonBit.",
  base_path: "/m/",
  site_url: "https://x.io/m/",
  repo_url: "https://github.com/moonrockz/moon-lander",
  packages: [],
  api: [],
  nav: None,
  chapters: [],
}

///|
fn meta(
  route : String,
  title : String,
  section : @model.Section,
) -> @views.PageMeta {
  { config, route, title, description: "d", section }
}

///|
let article : @model.ArticleSummary = {
  route: "/articles/hello/",
  title: "Hello",
  date: "2026-10-13",
  authors: ["Ada", "Zoë"],
  summary: "First article.",
}

///|
async test "layout has head, nav and main" {
  let m = meta("/docs/a/", "A", Docs)
  let out = @views.render(m, @views.raw("<p>hi</p>"))
  assert_true(
    out.has_prefix(
      "<!DOCTYPE html><html data-base=\"/m/\" data-site-root=\"/m/\" lang=\"en\">",
    ),
  )
  assert_true(out.contains("<title>A · Moon-Lander</title>"))
  assert_true(
    out.contains("<link href=\"/m/assets/site.css\" rel=\"stylesheet\">"),
  )
  assert_true(out.contains("href=\"/m/articles/atom.xml\""))
  assert_true(out.contains("href=\"/m/docs/\""))
  assert_true(out.contains("href=\"/m/articles/\""))
  assert_true(out.contains("class=\"current\""))
  assert_true(
    out.contains(
      "<main id=\"content\"><div class=\"prose\"><p>hi</p></div></main>",
    ),
  )
}

///|
async test "the theme script is in head before the stylesheet link" {
  let out = @views.render(meta("/docs/a/", "A", Docs), @views.raw("<p>hi</p>"))
  let head_end = out.find("</head>").unwrap()
  let script = out.find(@views.theme_script).unwrap()
  let stylesheet = out.find("<link href=\"/m/assets/site.css\"").unwrap()
  assert_true(script < stylesheet)
  assert_true(stylesheet < head_end)
}

///|
async test "islands mount in empty elements and read the base path" {
  let out = @views.render(meta("/docs/a/", "A", Docs), @views.raw("<p>hi</p>"))
  assert_true(out.contains("<html data-base=\"/m/\""))
  for id in ["site-search", "site-version", "site-theme", "site-nav"] {
    assert_true(out.contains("<div id=\"\{id}\"></div>"))
  }
  // A module script runs after the page is parsed, so it does not block the first paint.
  assert_true(
    out.contains("<script src=\"/m/assets/islands.js\" type=\"module\"></script>"),
  )
}

///|
async test "No JavaScript" {
  // The docs page has its sidebar, its content and plain links in the server-rendered HTML. The
  // islands only fill the empty mounts, so the page needs no island code.
  let nav : Array[@model.NavItem] = [
    { route: "/docs/", title: "Docs", depth: 0, proposed: false },
    { route: "/docs/a/", title: "A", depth: 0, proposed: false },
  ]
  let m = meta("/docs/a/", "A", Docs)
  let out = @views.render(
    m,
    @views.docs_page(m, nav, "<h1>A</h1><p>Body text.</p>", None),
  )
  assert_true(out.contains("<aside class=\"docs-sidebar\">"))
  assert_true(out.contains("<a href=\"/m/docs/\" target=\"_self\">Docs</a>"))
  assert_true(out.contains("<h1>A</h1><p>Body text.</p>"))
  assert_true(
    out.contains(
      "<nav aria-label=\"Main\" class=\"site-links\" id=\"site-links\"><a aria-current=\"page\" href=\"/m/docs/\"",
    ),
  )
  assert_true(out.contains("<a href=\"/m/articles/\" target=\"_self\">Articles</a>"))
}

///|
async test "proposed page" {
  let nav : Array[@model.NavItem] = [
    { route: "/docs/design/overview/", title: "Overview", depth: 0, proposed: true },
  ]
  let m = meta("/docs/design/overview/", "Overview", Docs)
  let out = @views.render(
    m,
    @views.docs_page(m, nav, "<h1>Overview</h1>", None, proposed=true),
  )
  assert_true(
    out.contains(
      "<p role=\"note\" class=\"status-banner\">Proposed — not implemented</p>",
    ),
    msg=out,
  )
  assert_true(
    out.contains("Overview <span class=\"badge\">Proposed</span></a>"),
    msg=out,
  )
  let plain = @views.render(m, @views.docs_page(m, [], "<h1>A</h1>", None))
  assert_false(plain.contains("status-banner"))
}

///|
async test "docs page has sidebar with current page and source link" {
  let nav : Array[@model.NavItem] = [
    { route: "", title: "Adr", depth: 0, proposed: false },
    { route: "/docs/adr/a/", title: "First", depth: 1, proposed: false },
  ]
  let m = meta("/docs/adr/a/", "First", Docs)
  let out = @views.render(
    m,
    @views.docs_page(
      m,
      nav,
      "<h1 id=\"first\">First</h1>",
      Some("https://g/x.md"),
    ),
  )
  assert_true(out.contains("<span class=\"nav-label\">Adr</span>"))
  assert_true(
    out.contains(
      "<li class=\"depth-1\"><a aria-current=\"page\" href=\"/m/docs/adr/a/\"",
    ),
  )
  assert_true(out.contains("aria-current=\"page\""))
  assert_true(out.contains("href=\"https://g/x.md\""))
}

///|
async test "docs page lists the page headings in an On this page rail" {
  let m = meta("/docs/a/", "A", Docs)
  let toc : Array[@model.TocEntry] = [
    { id: "overview", text: "Overview", depth: 0, },
    { id: "details", text: "Details & more", depth: 1, },
  ]
  let out = @views.render(m, @views.docs_page(m, [], "<h1>A</h1>", None, toc~))
  inspect(
    out[out.find("<nav aria-label=\"On this page\"").unwrap():out
    .find("</aside></div>")
    .unwrap()],
    content=(
      #|<nav aria-label="On this page" class="docs-toc" id="site-toc"><p class="nav-label">On this page</p><ul><li class="depth-0"><a href="#overview" target="_self">Overview</a></li><li class="depth-1"><a href="#details" target="_self">Details &amp; more</a></li></ul></nav>
    ),
  )
  let bare = @views.render(m, @views.docs_page(m, [], "<h1>A</h1>", None))
  assert_false(bare.contains("docs-toc"))
}

///|
async test "article page and articles index" {
  let m = meta("/articles/hello/", "Hello", Articles)
  let page = @views.render(m, @views.article_page(m, article, "<p>body</p>"))
  assert_true(page.contains("<h1>Hello</h1>"))
  assert_true(page.contains("<time datetime=\"2026-10-13\">2026-10-13</time>"))
  assert_true(page.contains("Ada, Zoë"))
  let index = @views.render(
    meta("/articles/", "Articles", Articles),
    @views.articles_index(meta("/articles/", "Articles", Articles), [article]),
  )
  assert_true(index.contains("href=\"/m/articles/hello/\""))
  assert_true(index.contains("First article."))
}

///|
async test "home page replaces the latest articles marker" {
  let m = meta("/", "Moon-Lander", Home)
  let landing = "<section class=\"hero\">h</section>" +
    @views.latest_articles_marker +
    "<section>after</section>"
  let out = @views.render(m, @views.home_page(m, landing, [article]))
  assert_true(out.contains("<title>Moon-Lander</title>"))
  assert_true(out.contains("<section class=\"hero\">h</section>"))
  assert_true(out.contains("href=\"/m/articles/hello/\""))
  assert_true(out.contains("<section>after</section>"))
  assert_false(out.contains("data-site=\"latest-articles\""))
}

///|
async test "snapshot: layout" {
  let out = @views.render(meta("/docs/a/", "A", Docs), @views.raw("<p>hi</p>"))
  inspect(
    out,
    content=(
      #|<!DOCTYPE html><html data-base="/m/" data-site-root="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>A · Moon-Lander</title><meta name="description" content="d"><script>try{var t=localStorage.getItem('site-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}</script><link href="/m/assets/site.css" rel="stylesheet"><link title="Moon-Lander articles" href="/m/articles/atom.xml" rel="alternate" type="application/atom+xml"><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand">Moon-Lander</a><nav aria-label="Main" class="site-links" id="site-links"><a aria-current="page" href="/m/docs/" target="_self" class="current">Docs</a><a href="/m/articles/" target="_self">Articles</a><a href="https://github.com/moonrockz/moon-lander" target="_self">GitHub</a></nav><div id="site-search"></div><div id="site-version"></div><div id="site-theme"></div><div id="site-nav"></div></header><div class="version-banner"></div><main id="content"><div class="prose"><p>hi</p></div></main><footer class="site-footer"><p>Apache-2.0 · Moon-Lander, an application framework for MoonBit</p></footer></body></html>



    ),
  )
}

///|
async test "snapshot: docs page" {
  let nav : Array[@model.NavItem] = [
    { route: "", title: "Adr", depth: 0, proposed: false },
    { route: "/docs/adr/a/", title: "First", depth: 1, proposed: false },
  ]
  let m = meta("/docs/adr/a/", "First", Docs)
  let out = @views.render(
    m,
    @views.docs_page(
      m,
      nav,
      "<h1 id=\"first\">First</h1>",
      Some("https://g/x.md"),
    ),
  )
  inspect(
    out,
    content=(
      #|<!DOCTYPE html><html data-base="/m/" data-site-root="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>First · Moon-Lander</title><meta name="description" content="d"><script>try{var t=localStorage.getItem('site-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}</script><link href="/m/assets/site.css" rel="stylesheet"><link title="Moon-Lander articles" href="/m/articles/atom.xml" rel="alternate" type="application/atom+xml"><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand">Moon-Lander</a><nav aria-label="Main" class="site-links" id="site-links"><a aria-current="page" href="/m/docs/" target="_self" class="current">Docs</a><a href="/m/articles/" target="_self">Articles</a><a href="https://github.com/moonrockz/moon-lander" target="_self">GitHub</a></nav><div id="site-search"></div><div id="site-version"></div><div id="site-theme"></div><div id="site-nav"></div></header><div class="version-banner"></div><main id="content"><div class="docs-layout"><aside class="docs-sidebar"><nav aria-label="Documentation"><ul><li class="depth-0"><span class="nav-label">Adr</span></li><li class="depth-1"><a aria-current="page" href="/m/docs/adr/a/" target="_self" class="current">First</a></li></ul></nav></aside><article class="docs-article"><div class="prose"><h1 id="first">First</h1></div><p class="page-source"><a href="https://g/x.md" target="_self">View source on GitHub</a></p></article></div></main><footer class="site-footer"><p>Apache-2.0 · Moon-Lander, an application framework for MoonBit</p></footer></body></html>



    ),
  )
}

///|
async test "snapshot: article page" {
  let m = meta("/articles/hello/", "Hello", Articles)
  inspect(
    @views.render(m, @views.article_page(m, article, "<p>body</p>")),
    content=(
      #|<!DOCTYPE html><html data-base="/m/" data-site-root="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Hello · Moon-Lander</title><meta name="description" content="d"><script>try{var t=localStorage.getItem('site-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}</script><link href="/m/assets/site.css" rel="stylesheet"><link title="Moon-Lander articles" href="/m/articles/atom.xml" rel="alternate" type="application/atom+xml"><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand">Moon-Lander</a><nav aria-label="Main" class="site-links" id="site-links"><a href="/m/docs/" target="_self">Docs</a><a aria-current="page" href="/m/articles/" target="_self" class="current">Articles</a><a href="https://github.com/moonrockz/moon-lander" target="_self">GitHub</a></nav><div id="site-search"></div><div id="site-version"></div><div id="site-theme"></div><div id="site-nav"></div></header><div class="version-banner"></div><main id="content"><article class="article"><header><h1>Hello</h1><p class="article-meta"><time datetime="2026-10-13">2026-10-13</time> · Ada, Zoë</p></header><div class="prose"><p>body</p></div></article></main><footer class="site-footer"><p>Apache-2.0 · Moon-Lander, an application framework for MoonBit</p></footer></body></html>



    ),
  )
}

///|
async test "snapshot: articles index" {
  let m = meta("/articles/", "Articles", Articles)
  inspect(
    @views.render(m, @views.articles_index(m, [article])),
    content=(
      #|<!DOCTYPE html><html data-base="/m/" data-site-root="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Articles · Moon-Lander</title><meta name="description" content="d"><script>try{var t=localStorage.getItem('site-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}</script><link href="/m/assets/site.css" rel="stylesheet"><link title="Moon-Lander articles" href="/m/articles/atom.xml" rel="alternate" type="application/atom+xml"><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand">Moon-Lander</a><nav aria-label="Main" class="site-links" id="site-links"><a href="/m/docs/" target="_self">Docs</a><a aria-current="page" href="/m/articles/" target="_self" class="current">Articles</a><a href="https://github.com/moonrockz/moon-lander" target="_self">GitHub</a></nav><div id="site-search"></div><div id="site-version"></div><div id="site-theme"></div><div id="site-nav"></div></header><div class="version-banner"></div><main id="content"><section class="articles-index"><h1>Articles</h1><p><a href="/m/articles/atom.xml" target="_self">Atom feed</a></p><ul class="article-list"><li class="article-card"><a href="/m/articles/hello/" target="_self">Hello</a><p class="article-meta"><time datetime="2026-10-13">2026-10-13</time> · Ada, Zoë</p><p>First article.</p></li></ul></section></main><footer class="site-footer"><p>Apache-2.0 · Moon-Lander, an application framework for MoonBit</p></footer></body></html>



    ),
  )
}

///|
async test "snapshot: home page" {
  let m = meta("/", "Moon-Lander", Home)
  let landing = "<section class=\"hero\">h</section>" +
    @views.latest_articles_marker +
    "<section>after</section>"
  inspect(
    @views.render(m, @views.home_page(m, landing, [article])),
    content=(
      #|<!DOCTYPE html><html data-base="/m/" data-site-root="/m/" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Moon-Lander</title><meta name="description" content="d"><script>try{var t=localStorage.getItem('site-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}</script><link href="/m/assets/site.css" rel="stylesheet"><link title="Moon-Lander articles" href="/m/articles/atom.xml" rel="alternate" type="application/atom+xml"><script src="/m/assets/islands.js" type="module"></script><script id="__rabbita_transcript" type="application/json">{}</script></head><body><a href="#content" target="_self" class="skip-link">Skip to content</a><header class="site-header"><a href="/m/" target="_self" class="brand">Moon-Lander</a><nav aria-label="Main" class="site-links" id="site-links"><a href="/m/docs/" target="_self">Docs</a><a href="/m/articles/" target="_self">Articles</a><a href="https://github.com/moonrockz/moon-lander" target="_self">GitHub</a></nav><div id="site-search"></div><div id="site-version"></div><div id="site-theme"></div><div id="site-nav"></div></header><div class="version-banner"></div><main id="content"><div class="home"><div class="landing"><section class="hero">h</section></div><section class="latest-articles"><h2>Latest articles</h2><ul class="article-list"><li class="article-card"><a href="/m/articles/hello/" target="_self">Hello</a><p class="article-meta"><time datetime="2026-10-13">2026-10-13</time> · Ada, Zoë</p><p>First article.</p></li></ul></section><div class="landing"><section>after</section></div></div></main><footer class="site-footer"><p>Apache-2.0 · Moon-Lander, an application framework for MoonBit</p></footer></body></html>



    ),
  )
}

///|
async test "a build writes an empty version banner and the site root" {
  let out = @views.render(meta("/docs/a/", "A", Docs), @views.raw("<p>hi</p>"))
  assert_true(
    out.contains("<div class=\"version-banner\"></div><main id=\"content\">"),
  )
  assert_true(out.contains("data-site-root=\"/m/\""))
  assert_false(out.contains("rel=\"canonical\""))
}
