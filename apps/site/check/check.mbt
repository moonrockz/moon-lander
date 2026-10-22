///|
/// The Atom feed of the articles, relative to the output directory.
let feed_file : String = "articles/atom.xml"

///|
/// The regular files below `dir`, as sorted paths relative to `dir` with `/`.
async fn site_files(dir : String, prefix~ : String = "") -> Array[String] {
  let out = []
  let base = if prefix == "" { dir } else { "\{dir}/\{prefix}" }
  for name in @fs.readdir(base, sort=true) {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{dir}/\{rel}") {
      Directory => out.append(site_files(dir, prefix=rel))
      Regular => out.push(rel)
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
/// problems: a missing `index.html`, each internal link that leaves the base path or has no regular
/// file, each page without a title, a missing or badly formed Atom feed, and each file below
/// `docs/superpowers/`.
async fn check_site(root : String, dir : String) -> Array[@model.Problem] {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file("\{root}/site/site.json").text(),
  )
  let problems = []
  if !@fs.exists("\{dir}/index.html") {
    problems.push(@model.problem(dir, "has no `index.html`"))
  }
  let files = site_files(dir)
  for file in files {
    if file.has_prefix(@model.forbidden_dir) {
      problems.push(
        @model.problem(
          file,
          "is below `\{@model.forbidden_dir}`, which never goes on the site",
        ),
      )
    }
  }
  if is_file("\{dir}/\{feed_file}") {
    match @model.xml_problem(@fs.read_file("\{dir}/\{feed_file}").text()) {
      Some(message) =>
        problems.push(@model.problem(feed_file, "is not well-formed XML: \{message}"))
      None => ()
    }
  } else {
    problems.push(@model.problem(feed_file, "is missing"))
  }
  for page in files.filter(file => file.has_suffix(".html")) {
    let html = @fs.read_file("\{dir}/\{page}").text()
    if !@model.has_title(html) {
      problems.push(@model.problem(page, "has no `<title>` text"))
    }
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
