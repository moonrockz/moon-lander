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
/// What goes between the item and the method in the anchor of a method of `impl_`: the trait name
/// below a type or an error, or the implementing type below a trait.
pub fn ApiImpl::via(self : ApiImpl, below_trait~ : Bool) -> String {
  if below_trait {
    self.self_type
  } else {
    self.trait_name
  }
}

///|
/// The anchors of the public items and methods of `api` that have no docstring, in page order. The
/// methods of trait implementations count too.
pub fn api_missing_docstrings(api : ApiPackage) -> Array[String] {
  let out = []
  let check_item = (item : ApiItem, below_trait : Bool) => {
    let name = item.entry.name
    if item.entry.docstring.trim() == "" {
      out.push(name)
    }
    for entry in item.methods {
      if entry.docstring.trim() == "" {
        out.push(api_method_anchor(name, entry.name))
      }
    }
    for impl_ in item.impls {
      let via = impl_.via(below_trait~)
      for entry in impl_.methods {
        if entry.docstring.trim() == "" {
          out.push(api_method_anchor(name, entry.name, via~))
        }
      }
    }
  }
  for item in api.types {
    check_item(item, false)
  }
  for item in api.errors {
    check_item(item, false)
  }
  for item in api.traits {
    check_item(item, true)
  }
  for entry in api.aliases + api.values {
    if entry.docstring.trim() == "" {
      out.push(entry.name)
    }
  }
  out
}

///|
/// The anchors of the items and methods on the API page of `api`, in page order: `#<item>`,
/// `#<Type>.<method>`, and the method anchors of trait implementations.
pub fn api_anchors(api : ApiPackage) -> Array[String] {
  let out = []
  let add_item = (item : ApiItem, below_trait : Bool) => {
    let name = item.entry.name
    out.push(name)
    for entry in item.methods {
      out.push(api_method_anchor(name, entry.name))
    }
    for impl_ in item.impls {
      let via = impl_.via(below_trait~)
      for entry in impl_.methods {
        out.push(api_method_anchor(name, entry.name, via~))
      }
    }
  }
  for item in api.types {
    add_item(item, false)
  }
  for item in api.errors {
    add_item(item, false)
  }
  for item in api.traits {
    add_item(item, true)
  }
  for entry in api.aliases + api.values {
    out.push(entry.name)
  }
  out
}

///|
/// `text` with each `%XX` escape of an ASCII character decoded. CommonMark writes some characters of
/// a link target as escapes, for example `[` as `%5B`. Other text, and an escape of a byte above 127,
/// stays as it is.
pub fn percent_decode(text : String) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < text.length() {
    let c = text.code_unit_at(i)
    if c == '%' && i + 2 < text.length() {
      match (hex_digit(text.code_unit_at(i + 1)), hex_digit(text.code_unit_at(i + 2))) {
        (Some(high), Some(low)) if high < 8 => {
          out.write_char(Int::unsafe_to_char(high * 16 + low))
          i += 3
          continue
        }
        _ => ()
      }
    }
    out.write_char(Int::unsafe_to_char(c.to_int()))
    i += 1
  }
  out.to_string()
}

///|
fn hex_digit(c : UInt16) -> Int? {
  let n = c.to_int()
  if n >= '0'.to_int() && n <= '9'.to_int() {
    Some(n - '0'.to_int())
  } else if n >= 'a'.to_int() && n <= 'f'.to_int() {
    Some(n - 'a'.to_int() + 10)
  } else if n >= 'A'.to_int() && n <= 'F'.to_int() {
    Some(n - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// The site link of the Markdown link target `api:<package path>[#<anchor>]`, or `Err` with the reason
/// when the package has no API page or the page has no such anchor. `anchors` maps each package path
/// on the site to the anchors of its page. The check uses the percent-decoded target, and the link
/// keeps the anchor as the target writes it.
pub fn api_prose_link(
  target : String,
  anchors~ : Map[String, Array[String]],
  base_path~ : String,
) -> Result[String, String] {
  let rest = if target.has_prefix("api:") {
    target[4:].to_owned()
  } else {
    target
  }
  let (package_part, anchor_part) = match rest.find("#") {
    Some(i) => (rest[:i].to_owned(), rest[i + 1:].to_owned())
    None => (rest, "")
  }
  let package_path = percent_decode(package_part)
  let anchor = percent_decode(anchor_part)
  guard anchors.get(package_path) is Some(found) else {
    return Err("no API page for the package `\{package_path}`")
  }
  if anchor != "" && !found.contains(anchor) {
    return Err("the API page of `\{package_path}` has no item or method `#\{anchor}`")
  }
  let page = base_path + api_route(package_path)[1:].to_owned()
  Ok(if anchor_part == "" { page } else { "\{page}#\{anchor_part}" })
}

///|
/// The first sentence of plain text: the text up to the first `.`, `!` or `?` that ends a word, or all
/// of the text.
pub fn first_sentence(text : String) -> String {
  let flat = text.split("\n").map(l => l.trim().to_owned()).collect().join(" ").trim().to_owned()
  for i in 0..<flat.length() {
    let c = flat.code_unit_at(i)
    if (c == '.' || c == '!' || c == '?') &&
      (i + 1 == flat.length() || flat.code_unit_at(i + 1) == ' ') {
      return flat[:i + 1].to_owned()
    }
  }
  flat
}

///|
/// The search entries of the items and methods of `api`, in page order. The route is the API page
/// with the anchor, the title is the name (`<Type>::<method>` for a method), the section is `API`,
/// the heading is the package path, and the summary is the first sentence of `plain(entry)`, the
/// docstring as plain text.
pub fn api_search_entries(
  api : ApiPackage,
  plain : (ApiEntry) -> String,
) -> Array[SearchEntry] {
  let out = []
  let route = api_route(api.path)
  let add = (anchor : String, title : String, entry : ApiEntry) => {
    let summary = first_sentence(plain(entry))
    out.push({
      route: "\{route}#\{anchor}",
      title,
      section: "API",
      summary,
      headings: [api.path],
      text: "\{api.path} \{summary}",
    })
  }
  let add_item = (item : ApiItem, below_trait : Bool) => {
    let name = item.entry.name
    add(name, name, item.entry)
    for entry in item.methods {
      add(api_method_anchor(name, entry.name), "\{name}::\{entry.name}", entry)
    }
    for impl_ in item.impls {
      let via = impl_.via(below_trait~)
      for entry in impl_.methods {
        add(
          api_method_anchor(name, entry.name, via~),
          "\{name}::\{entry.name}",
          entry,
        )
      }
    }
  }
  for item in api.types {
    add_item(item, false)
  }
  for item in api.errors {
    add_item(item, false)
  }
  for item in api.traits {
    add_item(item, true)
  }
  for entry in api.aliases + api.values {
    add(entry.name, entry.name, entry)
  }
  out
}
