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
/// The file at the root of an assembled site that lists its version trees (design D22).
let versions_file : String = "versions.json"

///|
/// Check the built site in `dir` against the configuration of the repository at `root`. `base` is the
/// base path of the site in `dir`, the `base_path` of `site/site.json` by default; a build of one
/// version tree, such as `_site/next/`, gives the base path of that tree. When `dir` has
/// `versions.json`, it is an assembled site, and each tree is checked as one site (the tree check).
/// Returns the problems: a missing `index.html`, each internal link that leaves the base path or has no
/// regular file, each page without a title, a missing or badly formed Atom feed, and each file below
/// `docs/superpowers/`.
async fn check_site(
  root : String,
  dir : String,
  base? : String,
) -> Array[@model.Problem] {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    @fs.read_file("\{root}/site/site.json").text(),
  )
  let base = base.unwrap_or(config.base_path)
  if !is_file("\{dir}/\{versions_file}") {
    return check_tree(dir, "", base, [], assembled=false)
  }
  let versions = @model.VersionsFile::parse(
    versions_file,
    @fs.read_file("\{dir}/\{versions_file}").text(),
  )
  let problems = []
  // The root tree holds the other trees; they are checked on their own.
  let skip = ["next/", "latest/", "v/"]
  for tree in versions.trees(base) {
    let (path, tree_base) = tree
    let others = if path == "" { skip } else { [] }
    problems.append(check_tree(dir, path, tree_base, others, assembled=true))
  }
  problems
}

///|
/// Check the tree at `path` below `dir`, with the base path `base`. Files below a directory in `skip`
/// belong to another tree. In an assembled site a link that leaves the tree names the tree; the banner
/// link is the one link that can leave it.
async fn check_tree(
  dir : String,
  path : String,
  base : String,
  skip : Array[String],
  assembled~ : Bool,
) -> Array[@model.Problem] {
  let tree_dir = if path == "" { dir } else { "\{dir}/\{path[:path.length() - 1]}" }
  let problems = []
  if !@fs.exists("\{tree_dir}/index.html") {
    problems.push(@model.problem(tree_dir, "has no `index.html`"))
  }
  let files = site_files(tree_dir).filter(file => !skip.iter().any(s => file.has_prefix(s)))
  for file in files {
    if file.has_prefix(@model.forbidden_dir) {
      problems.push(
        @model.problem(
          path + file,
          "is below `\{@model.forbidden_dir}`, which never goes on the site",
        ),
      )
    }
  }
  if is_file("\{tree_dir}/\{feed_file}") {
    match @model.xml_problem(@fs.read_file("\{tree_dir}/\{feed_file}").text()) {
      Some(message) =>
        problems.push(
          @model.problem(path + feed_file, "is not well-formed XML: \{message}"),
        )
      None => ()
    }
  } else {
    problems.push(@model.problem(path + feed_file, "is missing"))
  }
  for page in files.filter(file => file.has_suffix(".html")) {
    let html = @fs.read_file("\{tree_dir}/\{page}").text()
    if !@model.has_title(html) {
      problems.push(@model.problem(path + page, "has no `<title>` text"))
    }
    let html = if assembled { @model.without_banner(html) } else { html }
    for link in @model.internal_links(html) {
      match @model.link_file(base, link) {
        None =>
          problems.push(
            @model.problem(
              path + page,
              if assembled {
                "link `\{link}` leaves its tree `\{base}`"
              } else {
                "link `\{link}` leaves the base path `\{base}`"
              },
            ),
          )
        Some(file) =>
          if !is_file("\{tree_dir}/\{file}") {
            problems.push(
              @model.problem(path + page, "broken internal link `\{link}`"),
            )
          }
      }
    }
  }
  problems
}
