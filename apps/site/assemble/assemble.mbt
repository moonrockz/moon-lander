///|
/// Consumer release discovery supplies the checked trees; Telescope assembles them.
struct Plan {
  base : String
  site_url : String
  lines : Array[String]
}

///|
async fn write_text(path : String, text : String) -> Unit {
  @fs.mkdir(@host.parent(path), recursive=true, allow_exist=true)
  @fs.write_file(path, text, create_mode=CreateOrTruncate)
}

///|
/// Stage retained archives outside the destination so a failed assembly keeps the old site.
async fn stage_tree(from : String, to : String) -> Unit {
  @fs.mkdir(to, recursive=true, allow_exist=true)
  for name in @fs.readdir(from, include_hidden=true) {
    let source = "\{from}/\{name}"
    let target = "\{to}/\{name}"
    match @fs.kind(source, follow_symlink=false) {
      Directory => stage_tree(source, target)
      Regular => @fs.write_file(target, @fs.read_file(source).binary(), create_mode=CreateOrTruncate)
      _ => raise @model.Invalid([@model.problem(source, "site archive entries must be regular files or directories")])
    }
  }
}

///|
async fn assemble_site(dir : String, plan : Plan) -> Unit {
  let input = @fs.tmpdir(prefix="lander-site-trees")
  defer @fs.rmdir(input, recursive=true)
  let trees : Array[Json] = []
  for id in ["next", ..plan.lines] {
    let path = @model.tree_path(id).trim_end(chars="/").to_owned()
    stage_tree("\{dir}/\{path}", "\{input}/\{path}")
    trees.push({ "id": id, "path": path, "base_path": plan.base + @model.tree_path(id) })
  }
  let manifest : Json = {
    "schema_version": 1,
    "base_path": plan.base,
    "site_url": plan.site_url,
    "latest": match plan.lines.get(0) { Some(line) => Json(line); None => Json::null() },
    "trees": trees,
  }
  let file = input + "/versions-input.json"
  write_text(file, manifest.stringify())
  @host.assemble(file, dir)
  for tree in ["", "next/", ..plan.lines.map(@model.tree_path)] {
    label_pages(dir, plan, tree)
  }
  if !plan.lines.is_empty() { label_pages(dir, plan, "latest/") }
}

///|
/// Keep Moon-Lander's published banner wording and fallback links after shared assembly.
async fn label_pages(dir : String, plan : Plan, tree : String, prefix~ : String = "") -> Unit {
  let location = if tree == "" { dir } else { "\{dir}/\{tree.trim_end(chars="/")}" }
  let folder = if prefix == "" { location } else { "\{location}/\{prefix}" }
  for name in @fs.readdir(folder) {
    if tree == "" && prefix == "" && ["next", "v", "latest"].contains(name) { continue }
    let path = if prefix == "" { name } else { "\{prefix}/\{name}" }
    if @fs.kind("\{location}/\{path}") is Directory {
      label_pages(dir, plan, tree, prefix=path)
      continue
    }
    if !path.has_suffix(".html") { continue }
    let file = "\{location}/\{path}"
    let original = @fs.read_file(file).text()
    let empty = @model.banner_start + "</div>"
    let latest = plan.lines.get(0)
    let banner = match latest {
      None => "<p>Pre-release docs. No version is released yet. These pages show <code>main</code>.</p>"
      Some(line) if tree == "next/" =>
        "<p>You are reading docs for <code>main</code>, which is not released. The latest is \{line}.</p>"
      Some(line) if tree.has_prefix("v/") && tree != @model.tree_path(line) => {
        let old = tree[2:tree.length() - 1].to_owned()
        let route = if path == "index.html" { "" } else if path.has_suffix("/index.html") {
          path[:path.length() - "index.html".length()].to_owned()
        } else { path }
        let link = plan.base + "latest/" + (if @fs.exists("\{dir}/latest/\{path}") { route } else { "" })
        "<p>You are reading \{old} docs. The latest is \{line}. <a href=\"\{link}\">Open the latest docs</a>.</p>"
      }
      _ => ""
    }
    let mut html = @model.without_banner(original).replace(old=empty, new=@model.banner_start + banner + "</div>")
    if tree == "latest/" && plan.site_url != "" {
      let route = if path == "index.html" { "" } else if path.has_suffix("/index.html") {
        path[:path.length() - "index.html".length()].to_owned()
      } else { path }
      html = html.replace_all(old="<link rel=\"canonical\" href=\"\{plan.site_url}latest/\{route}\">", new="")
    }
    if html != original { write_text(file, html) }
  }
}
