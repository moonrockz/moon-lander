///|
/// Under `moon test` the working directory is the module root, `apps/site`.
async fn site_dir(name : String, pages : Array[(String, String)]) -> String {
  let dir = "_build/check-\{name}"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  for page in pages {
    let (path, text) = page
    let file = "\{dir}/\{path}"
    match file.rev_find("/") {
      Some(i) => @fs.mkdir(file[:i].to_owned(), recursive=true, allow_exist=true)
      None => ()
    }
    @fs.write_file(file, text)
  }
  dir
}

///|
/// A page with a title and the body `body`.
fn page(body : String) -> String {
  "<html><head><title>Page</title></head><body>\{body}</body></html>"
}

///|
/// A well-formed Atom feed.
let feed : (String, String) = (
  "articles/atom.xml", "<?xml version=\"1.0\"?><feed><title>T</title></feed>",
)

///|
async test "a built site with valid links passes" {
  let dir = site_dir("valid", [
    (
      "index.html",
      page(
        "<link href=\"/fixture/assets/site.css\"><a href=\"/fixture/docs/#x\">d</a>",
      ),
    ),
    ("docs/index.html", page("<a href=\"/fixture/\">home</a>")),
    ("assets/site.css", ""),
    feed,
  ])
  assert_eq(check_site("fixtures/content", dir), [])
}

///|
async test "Broken internal link" {
  let dir = site_dir("broken", [
    (
      "index.html",
      page(
        "<a href=\"/fixture/docs/missing/\">m</a><a href=\"/elsewhere/\">e</a><a href=\"/fixture/assets\">a</a><a href=\"/fixture/../index.html\">p</a>",
      ),
    ),
    ("assets/site.css", ""),
    feed,
  ])
  assert_eq(check_site("fixtures/content", dir).map(p => p.render()), [
    "index.html: broken internal link `/fixture/docs/missing/`",
    "index.html: link `/elsewhere/` leaves the base path `/fixture/`",
    "index.html: broken internal link `/fixture/assets`",
    "index.html: link `/fixture/../index.html` leaves the base path `/fixture/`",
  ])
}

///|
async test "a site without index.html fails" {
  let dir = site_dir("empty", [("docs/index.html", page("")), feed])
  assert_eq(check_site("fixtures/content", dir).map(p => p.render()), [
    "\{dir}: has no `index.html`",
  ])
}

///|
async test "a page without title text fails" {
  let dir = site_dir("untitled", [
    ("index.html", page("")),
    ("docs/index.html", "<html><head><title> </title></head></html>"),
    feed,
  ])
  assert_eq(check_site("fixtures/content", dir).map(p => p.render()), [
    "docs/index.html: has no `<title>` text",
  ])
}

///|
async test "a missing or badly formed feed fails" {
  let missing = site_dir("no-feed", [("index.html", page(""))])
  assert_eq(check_site("fixtures/content", missing).map(p => p.render()), [
    "articles/atom.xml: is missing",
  ])
  let bad = site_dir("bad-feed", [
    ("index.html", page("")),
    ("articles/atom.xml", "<feed><entry></feed>"),
  ])
  assert_eq(check_site("fixtures/content", bad).map(p => p.render()), [
    "articles/atom.xml: is not well-formed XML: `</feed>` closes `<entry>`",
  ])
}

///|
async test "a file below docs/superpowers fails" {
  let dir = site_dir("plans", [
    ("index.html", page("")),
    ("docs/superpowers/plan/index.html", page("")),
    feed,
  ])
  assert_eq(check_site("fixtures/content", dir).map(p => p.render()), [
    "docs/superpowers/plan/index.html: is below `docs/superpowers/`, which never goes on the site",
  ])
}
