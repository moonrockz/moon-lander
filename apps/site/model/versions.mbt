///|
/// The first route segments that the version trees use (design D22). A source page must not have one
/// of them, because the deploy puts a tree at that path.
pub let reserved_segments : Array[String] = ["v", "next", "latest"]

///|
/// Whether the first segment of `route` is a version tree segment. `route` starts with `/`.
pub fn reserved_route(route : String) -> Bool {
  let rest = route[1:].to_owned()
  let first = match rest.find("/") {
    Some(i) => rest[:i].to_owned()
    None => rest
  }
  reserved_segments.contains(first)
}

///|
/// Whether `text` is a minor line `X.Y` with digits only, such as `0.2`.
pub fn is_minor_line(text : String) -> Bool {
  let parts = text.split(".").collect()
  parts.length() == 2 &&
  parts.iter().all(part => part != "" && part.iter().all(c => c >= '0' && c <= '9'))
}

///|
/// The path of the tree `tree` below the site root, with a final `/`: `next/` for `next` and
/// `v/<minor>/` for a minor line.
pub fn tree_path(tree : String) -> String {
  if tree == "next" {
    "next/"
  } else {
    "v/\{tree}/"
  }
}

///|
/// The site root of a page whose tree base path is `base`. A tree below `next/`, `latest/` or
/// `v/<minor>/` has the site root above that path; any other base path is the site root.
pub fn site_root(base : String) -> String {
  for suffix in ["next/", "latest/"] {
    if base.has_suffix("/" + suffix) {
      return base[:base.length() - suffix.length()].to_owned()
    }
  }
  let trimmed = base[:base.length() - 1].to_owned()
  match trimmed.rev_find("/") {
    Some(i) if is_minor_line(trimmed[i + 1:].to_owned()) => {
      let parent = trimmed[:i + 1].to_owned()
      if parent.has_suffix("/v/") {
        parent[:parent.length() - 2].to_owned()
      } else {
        base
      }
    }
    _ => base
  }
}

///|
/// The search index of the tree with the base path `base`. Each tree has its own index.
pub fn search_index_url(base : String) -> String {
  base + "search-index.json"
}

///|
/// The base path of the version choice `choice` below the site root `root`: `latest`, `next` or a
/// minor line.
pub fn choice_base(root : String, choice : String) -> String {
  if choice == "latest" {
    root + "latest/"
  } else {
    root + tree_path(choice)
  }
}

///|
/// The version choice of the tree with the base path `base` below the site root `root`: `latest`,
/// `next` or a minor line. The root tree shows the latest release, or `main` before the first release.
pub fn current_choice(root : String, base : String, latest : String?) -> String {
  let rest = if base.has_prefix(root) {
    base[root.length():].to_owned()
  } else {
    ""
  }
  if rest == "latest/" {
    "latest"
  } else if rest == "next/" {
    "next"
  } else if rest.has_prefix("v/") && rest.has_suffix("/") && rest.length() > 3 {
    rest[2:rest.length() - 1].to_owned()
  } else if latest is Some(_) {
    "latest"
  } else {
    "next"
  }
}

///|
/// The choices of the version switcher for `versions.json`: `latest` when a release exists, `next`,
/// then each kept minor line.
pub fn VersionsFile::choices(self : VersionsFile) -> Array[String] {
  let found = if self.latest is Some(_) { ["latest"] } else { [] }
  if self.next {
    found.push("next")
  }
  found + self.versions
}

///|
/// The label of the version choice `choice`.
pub fn choice_label(choice : String, latest : String?) -> String {
  match (choice, latest) {
    ("latest", Some(line)) => "Latest (\{line})"
    ("next", _) => "main"
    _ => choice
  }
}

///|
/// The page of the current path `path` in the tree with the base path `target`. The current page is in
/// the tree with the base path `base`. The switcher asks the host for this page first.
pub fn switch_probe(path : String, base : String, target : String) -> String {
  if path.has_prefix(base) {
    target + path[base.length():].to_owned()
  } else {
    target
  }
}

///|
/// The page that the version switcher opens: the same page in the target tree when it exists, or else
/// the root of the target tree.
pub fn switch_url(
  path : String,
  base : String,
  target : String,
  exists : Bool,
) -> String {
  if exists {
    switch_probe(path, base, target)
  } else {
    target
  }
}

///|
/// The file `versions.json` at the root of an assembled site (design D22): the newest release line,
/// whether the `next` tree exists, and each kept minor line, newest first. `latest` is `None` before
/// the first release.
pub(all) struct VersionsFile {
  latest : String?
  next : Bool
  versions : Array[String]
} derive(Eq, Debug)

///|
pub extend VersionsFile with Eq::{equal, not_equal}

///|
pub extend VersionsFile with @debug.Debug::{to_repr}

///|
/// The text of `versions.json`, for example
/// `{ "latest": "0.2", "next": true, "versions": ["0.2", "0.1"] }`.
pub fn VersionsFile::to_text(self : VersionsFile) -> String {
  let latest = match self.latest {
    Some(line) => "\"\{line}\""
    None => "null"
  }
  let versions = self.versions.map(line => "\"\{line}\"").join(", ")
  "{ \"latest\": \{latest}, \"next\": \{self.next}, \"versions\": [\{versions}] }\n"
}

///|
/// Parse the text of `versions.json`. `file` names the file in a problem.
pub fn VersionsFile::parse(
  file : String,
  text : String,
) -> VersionsFile raise Invalid {
  let json = @json.parse(text) catch {
    error => raise Invalid([problem(file, "not valid JSON: \{error}")])
  }
  guard json is Object(fields) else {
    raise Invalid([problem(file, "must be a JSON object")])
  }
  let latest = match fields.get("latest") {
    Some(String(line)) if is_minor_line(line) => Some(line)
    Some(Null) => None
    _ => raise Invalid([problem(file, "`latest` must be a minor line or null")])
  }
  let next = match fields.get("next") {
    Some(True) => true
    Some(False) => false
    _ => raise Invalid([problem(file, "`next` must be true or false")])
  }
  guard fields.get("versions") is Some(Array(items)) &&
    items.iter().all(item => item is String(line) && is_minor_line(line)) else {
    raise Invalid([problem(file, "`versions` must be an array of minor lines")])
  }
  let versions = items.filter_map(item => if item is String(line) {
    Some(line)
  } else {
    None
  })
  { latest, next, versions }
}

///|
/// The trees of an assembled site below the site root `root`: the directory of each tree relative to
/// the site directory, and its base path. The root tree comes first and has the directory `""`.
pub fn VersionsFile::trees(
  self : VersionsFile,
  root : String,
) -> Array[(String, String)] {
  let trees = [("", root)]
  if self.latest is Some(_) {
    trees.push(("latest/", root + "latest/"))
  }
  if self.next {
    trees.push(("next/", root + "next/"))
  }
  for line in self.versions {
    trees.push((tree_path(line), root + tree_path(line)))
  }
  trees
}

///|
/// The start of the version banner element that the layout writes (design D22).
pub let banner_start : String = "<div class=\"version-banner\">"

///|
/// `html` without the content of its version banner. The banner link is the one link of a page that
/// can leave its tree, so the tree check reads the page without it.
pub fn without_banner(html : String) -> String {
  guard html.find(banner_start) is Some(start) else { return html }
  let from = start + banner_start.length()
  guard html[from:].find("</div>") is Some(end) else { return html }
  html[:from].to_owned() + html[from + end:].to_owned()
}
