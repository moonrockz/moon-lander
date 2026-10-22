///|
/// Order by code unit, so the file lists do not depend on the platform.
fn compare_units(a : String, b : String) -> Int {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shared {
    let x = a.code_unit_at(i).to_int()
    let y = b.code_unit_at(i).to_int()
    if x != y {
      return x - y
    }
  }
  a.length() - b.length()
}

///|
/// Every regular file below `root`, as sorted paths relative to `root` with `/`.
async fn list_files(root : String, prefix~ : String = "") -> Array[String] {
  let out = []
  let dir = if prefix == "" { root } else { "\{root}/\{prefix}" }
  for name in @fs.readdir(dir) {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{root}/\{rel}") {
      Directory => out.append(list_files(root, prefix=rel))
      Regular => out.push(rel)
      _ => ()
    }
  }
  out.sort_by(compare_units)
  out
}

///|
async fn write_bytes(path : String, data : Bytes) -> Unit {
  match path.rev_find("/") {
    Some(i) => @fs.mkdir(path[:i].to_owned(), recursive=true, allow_exist=true)
    None => ()
  }
  @fs.write_file(path, data, create_mode=CreateOrTruncate)
}

///|
async fn write_text(path : String, text : String) -> Unit {
  match path.rev_find("/") {
    Some(i) => @fs.mkdir(path[:i].to_owned(), recursive=true, allow_exist=true)
    None => ()
  }
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
/// Whether the base path of a tree can occur in the file `path`: its links, its feed URLs, its
/// search data and its styles. Other files, such as images, are copied byte for byte.
fn has_links(path : String) -> Bool {
  [".html", ".xml", ".json", ".css"].iter().any(ext => path.has_suffix(ext))
}

///|
/// `text` with each `from` replaced by `to`. Every internal link of a tree starts with the tree base
/// path, so the copy of a tree at another base path is a prefix change (design D22).
fn rebase(text : String, from : String, to : String) -> String {
  text.replace_all(old=from, new=to)
}

///|
/// Copy the tree in `from_dir`, built with the base path `from_base`, to `to_dir` with the base path
/// `to_base`. Files below a directory in `skip` are not copied.
async fn copy_tree(
  from_dir : String,
  from_base : String,
  to_dir : String,
  to_base : String,
  skip~ : Array[String] = [],
) -> Unit {
  for file in list_files(from_dir) {
    if skip.iter().any(s => file.has_prefix(s)) {
      continue
    }
    let data = @fs.read_file("\{from_dir}/\{file}")
    if has_links(file) {
      write_text("\{to_dir}/\{file}", rebase(data.text(), from_base, to_base))
    } else {
      write_bytes("\{to_dir}/\{file}", data.binary())
    }
  }
}

///|
/// The banner of a page (design D22).
enum Banner {
  /// No release at or above `versions.since` exists yet.
  PreRelease
  /// A page of the minor line `line`, which is older than `latest`. The link opens the same page under
  /// `/latest/`, or `/latest/` when that page does not exist.
  Older(line~ : String, latest~ : String, link~ : String)
  /// A page of `main` after the first release `latest`.
  Unreleased(latest~ : String)
} derive(Eq, Debug)

///|
/// The HTML of a banner, for the version banner element.
fn banner_html(banner : Banner) -> String {
  match banner {
    PreRelease =>
      "<p>Pre-release docs. No version is released yet. These pages show <code>main</code>.</p>"
    Older(line~, latest~, link~) =>
      "<p>You are reading \{line} docs. The latest is \{latest}. <a href=\"\{link}\">Open the latest docs</a>.</p>"
    Unreleased(latest~) =>
      "<p>You are reading docs for <code>main</code>, which is not released. The latest is \{latest}.</p>"
  }
}

///|
/// The empty version banner that the layout writes.
let empty_banner : String = @model.banner_start + "</div>"

///|
/// `html` with the banner `banner` in its version banner element and the canonical link `canonical`
/// in its head. A page without the element or a head keeps that part as it is.
fn fill_page(html : String, banner : Banner?, canonical : String?) -> String {
  let html = match banner {
    Some(banner) =>
      html.replace(
        old=empty_banner,
        new=@model.banner_start + banner_html(banner) + "</div>",
      )
    None => html
  }
  match canonical {
    Some(url) =>
      html.replace(old="</head>", new="<link rel=\"canonical\" href=\"\{url}\"></head>")
    None => html
  }
}

///|
/// The route of the page file `file` of a tree, relative to the tree: `docs/index.html` gives
/// `docs/`, and `index.html` gives the empty route.
fn page_route(file : String) -> String {
  if file == "index.html" {
    ""
  } else if file.has_suffix("/index.html") {
    file[:file.length() - "index.html".length()].to_owned()
  } else {
    file
  }
}

///|
/// The site to assemble in `dir`: its base path and URL, the minor lines of the unpacked release
/// trees below `<dir>/v/`, newest first, and the `next` tree that the build wrote to `<dir>/next/`.
struct Plan {
  base : String
  site_url : String
  lines : Array[String]
}

///|
/// Assemble the site in `dir` (design D22). The newest release line is copied to `/latest/` and to the
/// root; before the first release, the `next` tree is copied to the root and no `/latest/` tree is
/// written. Then each page gets its banner and its canonical link, and `versions.json` lists the trees.
async fn assemble_site(dir : String, plan : Plan) -> Unit {
  let base = plan.base
  let latest = plan.lines.get(0)
  let skip = ["next/", "latest/", "v/"]
  match latest {
    Some(line) => {
      let tree = "\{dir}/v/\{line}"
      let tree_base = base + @model.tree_path(line)
      copy_tree(tree, tree_base, "\{dir}/latest", base + "latest/")
      copy_tree(tree, tree_base, dir, base)
    }
    None => copy_tree("\{dir}/next", base + "next/", dir, base)
  }
  // The pages of each tree: the tree directory relative to `dir`, and its banner rule.
  let trees : Array[(String, String?)] = [("", None), ("next/", Some("next"))]
  for line in plan.lines {
    trees.push((@model.tree_path(line), Some(line)))
  }
  for entry in trees {
    let (path, line) = entry
    let tree_dir = if path == "" { dir } else { "\{dir}/\{path[:path.length() - 1]}" }
    let files = list_files(tree_dir).filter(file => file.has_suffix(".html") &&
      !(path == "" && skip.iter().any(s => file.has_prefix(s))))
    for file in files {
      let route = page_route(file)
      let in_latest = latest is Some(_) && @fs.exists("\{dir}/latest/\{file}")
      let canonical = if in_latest {
        Some("\{plan.site_url}latest/\{route}")
      } else {
        None
      }
      let banner = match (latest, line) {
        (None, _) => Some(PreRelease)
        (Some(newest), Some("next")) => Some(Unreleased(latest=newest))
        (Some(newest), Some(old)) if old != newest => {
          let link = if in_latest {
            "\{base}latest/\{route}"
          } else {
            "\{base}latest/"
          }
          Some(Older(line=old, latest=newest, link~))
        }
        _ => None
      }
      let page = "\{tree_dir}/\{file}"
      let html = @fs.read_file(page).text()
      let filled = fill_page(html, banner, canonical)
      if filled != html {
        write_text(page, filled)
      }
    }
  }
  let versions : @model.VersionsFile = {
    latest,
    next: true,
    versions: plan.lines,
  }
  write_text("\{dir}/versions.json", versions.to_text())
}
