///|
/// One part of a signature: text, or a link with its `moon doc` target and its text.
pub(all) enum SignaturePart {
  Text(String)
  /// `Link(target, text)`: the target is `<package path>` or `<package path>#<item>`.
  Link(String, String)
} derive(Eq, Debug)

///|
pub extend SignaturePart with Eq::{equal, not_equal}

///|
pub extend SignaturePart with @debug.Debug::{to_repr}

///|
let link_start : String = "<a href=\""

///|
let link_end : String = "</a>"

///|
/// Split the signature HTML of `moon doc` into text and links. The only markup is
/// `<a href="<target>">` and `</a>`; every other character is text, so `-> N?` stays text. An `<a>`
/// tag without `href`, a link that is not closed, or a stray `</a>` is an error: the result is
/// `Err` with the reason.
pub fn parse_signature(signature : String) -> Result[Array[SignaturePart], String] {
  let parts : Array[SignaturePart] = []
  let text = StringBuilder()
  let mut rest = signature[:]
  while rest.find("<") is Some(i) {
    text.write_view(rest[:i])
    let tag = rest[i:]
    if tag.has_prefix(link_start) {
      let after = tag[link_start.length():]
      guard after.find("\">") is Some(close) else {
        return Err("an `<a>` tag is not closed")
      }
      let target = after[:close].to_owned()
      let inner = after[close + 2:]
      guard inner.find(link_end) is Some(end) else {
        return Err("the link to `\{target}` has no `</a>`")
      }
      let label = inner[:end]
      if label.contains("<a") {
        return Err("the link to `\{target}` has a link in it")
      }
      if target == "" {
        return Err("an `<a>` tag has an empty `href`")
      }
      if text.to_string() != "" {
        parts.push(Text(text.to_string()))
        text.reset()
      }
      parts.push(Link(target, label.to_owned()))
      rest = inner[end + link_end.length():]
    } else if tag.has_prefix("<a>") || tag.has_prefix("<a ") {
      return Err("an `<a>` tag has no `href`")
    } else if tag.has_prefix(link_end) {
      return Err("a `</a>` tag has no `<a>`")
    } else {
      text.write_char('<')
      rest = tag[1:]
    }
  }
  text.write_view(rest)
  if text.to_string() != "" {
    parts.push(Text(text.to_string()))
  }
  Ok(parts)
}

///|
/// The route of the API page of a package: `/api/<package path>/`.
pub fn api_route(package_path : String) -> String {
  "/api/\{package_path}/"
}

///|
/// The link of a signature target from the page of `current`, or `None` for plain text. A target in
/// `current` becomes `#<item>`. A target in another package of `site_packages` becomes
/// `<base_path>api/<package path>/#<item>`. A target outside the site has no link.
pub fn api_link(
  target : String,
  current~ : String,
  site_packages~ : Array[String],
  base_path~ : String,
) -> String? {
  let (package_path, item) = match target.find("#") {
    Some(i) => (target[:i].to_owned(), target[i + 1:].to_owned())
    None => (target, "")
  }
  let anchor = if item == "" { "" } else { "#\{item}" }
  if package_path == current && item != "" {
    Some(anchor)
  } else if site_packages.contains(package_path) {
    Some(base_path + api_route(package_path)[1:].to_owned() + anchor)
  } else {
    None
  }
}

///|
/// The GitHub link of the source of an API item at `commit`. `module_dir` is the module directory in
/// the repository, such as `pkgs/notebooks`, and `module_name` is the module name, such as
/// `moonrockz/notebooks`. The package directory is `loc.path` without the module name.
pub fn api_source_url(
  repo_url~ : String,
  commit~ : String,
  module_dir~ : String,
  module_name~ : String,
  loc : ApiLoc,
) -> String {
  let sub = if loc.path.has_prefix(module_name + "/") {
    "/" + loc.path[module_name.length() + 1:].to_owned()
  } else {
    ""
  }
  "\{repo_url}/blob/\{commit}/\{module_dir}\{sub}/\{loc.file}#L\{loc.line}"
}

///|
/// The anchor of a method of `item`. A method of an implementation has `via` between the item and the
/// method: the trait name below a type, because a type can have a method and a trait method with one
/// name, or the implementing type below a trait. An anchor has no spaces.
pub fn api_method_anchor(
  item : String,
  name : String,
  via~ : String = "",
) -> String {
  if via == "" {
    "\{item}.\{name}"
  } else {
    "\{item}.\{via.replace_all(old=" ", new="")}.\{name}"
  }
}

///|
/// The anchors of the public items and methods of `package` that have no docstring, in page order.
pub fn api_missing_docstrings(api : ApiPackage) -> Array[String] {
  let out = []
  let check_item = (item : ApiItem) => {
    if item.entry.docstring.trim() == "" {
      out.push(item.entry.name)
    }
    for entry in item.methods {
      if entry.docstring.trim() == "" {
        out.push(api_method_anchor(item.entry.name, entry.name))
      }
    }
  }
  for item in api.types {
    check_item(item)
  }
  for item in api.errors {
    check_item(item)
  }
  for item in api.traits {
    check_item(item)
  }
  for entry in api.aliases + api.values {
    if entry.docstring.trim() == "" {
      out.push(entry.name)
    }
  }
  out
}
