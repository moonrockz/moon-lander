///|
/// The `.html` files below `dir`, as sorted paths relative to `dir` with `/`.
async fn html_files(dir : String, prefix~ : String = "") -> Array[String] {
  let out = []
  let base = if prefix == "" { dir } else { "\{dir}/\{prefix}" }
  for name in @fs.readdir(base, sort=true) {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{dir}/\{rel}") {
      Directory => out.append(html_files(dir, prefix=rel))
      Regular if name.has_suffix(".html") => out.push(rel)
      _ => ()
    }
  }
  out
}

///|
/// Whether `path` is a regular file. A directory does not count, because the host does not serve it
/// without `index.html`.
async fn is_file(path : String) -> Bool {
  @fs.exists(path) && @fs.kind(path) is Regular
}

///|
/// Check the built site in `dir` against the configuration of the repository at `root`. Returns the
/// problems: a missing `index.html`, and each internal link that leaves the base path or has no regular file.
async fn check_site(root : String, dir : String) -> Array[@model.Problem] {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file("\{root}/site/site.json").text(),
  )
  let problems = []
  if !@fs.exists("\{dir}/index.html") {
    problems.push(@model.problem(dir, "has no `index.html`"))
  }
  for page in html_files(dir) {
    let html = @fs.read_file("\{dir}/\{page}").text()
    for link in @model.internal_links(html) {
      match @model.link_file(config.base_path, link) {
        None =>
          problems.push(
            @model.problem(
              page,
              "link `\{link}` leaves the base path `\{config.base_path}`",
            ),
          )
        Some(file) =>
          if !is_file("\{dir}/\{file}") {
            problems.push(@model.problem(page, "broken internal link `\{link}`"))
          }
      }
    }
  }
  problems
}
