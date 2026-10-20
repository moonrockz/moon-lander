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
async test "a built site with valid links passes" {
  let dir = site_dir("valid", [
    (
      "index.html", "<link href=\"/fixture/assets/site.css\"><a href=\"/fixture/docs/#x\">d</a>",
    ),
    ("docs/index.html", "<a href=\"/fixture/\">home</a>"),
    ("assets/site.css", ""),
  ])
  assert_eq(check_site("fixtures/content", dir), [])
}

///|
async test "broken internal link" {
  let dir = site_dir("broken", [
    ("index.html", "<a href=\"/fixture/missing/\">m</a><a href=\"/elsewhere/\">e</a>"),
  ])
  assert_eq(check_site("fixtures/content", dir).map(p => p.render()), [
    "index.html: broken internal link `/fixture/missing/`",
    "index.html: link `/elsewhere/` does not start with the base path `/fixture/`",
  ])
}

///|
async test "a site without index.html fails" {
  let dir = site_dir("empty", [("docs/index.html", "")])
  assert_eq(check_site("fixtures/content", dir).map(p => p.render()), [
    "\{dir}: has no `index.html`",
  ])
}
