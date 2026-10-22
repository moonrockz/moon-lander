///|
fn is_space(c : Int) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}'
}

///|
/// The lower case of an ASCII letter, or `c` itself.
fn lower(c : Int) -> Int {
  if c >= 'A' && c <= 'Z' {
    c + 32
  } else {
    c
  }
}

///|
/// Whether the attribute name `name` (lower case) starts at `i` of `html`, after white space.
fn attribute_at(html : String, i : Int, name : String) -> Bool {
  if i == 0 || !is_space(html.code_unit_at(i - 1).to_int()) {
    return false
  }
  if i + name.length() > html.length() {
    return false
  }
  for k in 0..<name.length() {
    if lower(html.code_unit_at(i + k).to_int()) != name.code_unit_at(k).to_int() {
      return false
    }
  }
  true
}

///|
/// The attribute value that follows the name ending at `i`, and the index after it. The value can
/// be double-quoted, single-quoted or unquoted, with white space around `=`.
fn attribute_value(html : String, i : Int) -> (String, Int)? {
  let n = html.length()
  let mut j = i
  while j < n && is_space(html.code_unit_at(j).to_int()) {
    j += 1
  }
  guard j < n && html.code_unit_at(j).to_int() == '=' else { return None }
  j += 1
  while j < n && is_space(html.code_unit_at(j).to_int()) {
    j += 1
  }
  guard j < n else { return None }
  let quote = html.code_unit_at(j).to_int()
  if quote == '"' || quote == '\'' {
    let start = j + 1
    let mut end = start
    while end < n && html.code_unit_at(end).to_int() != quote {
      end += 1
    }
    Some((html[start:end].to_owned(), end + 1))
  } else {
    let mut end = j
    while end < n &&
          !is_space(html.code_unit_at(end).to_int()) &&
          html.code_unit_at(end).to_int() != '>' {
      end += 1
    }
    Some((html[j:end].to_owned(), end))
  }
}

///|
/// The `href` and `src` attribute values in `html` that start with `/`, in page order. Attribute
/// names match in any case, and values can be double-quoted, single-quoted or unquoted. A value that
/// starts with `//` is a link to another host, so it is not included.
pub fn internal_links(html : String) -> Array[String] {
  let found = []
  let mut i = 0
  while i < html.length() {
    let name = if attribute_at(html, i, "href") {
      "href"
    } else if attribute_at(html, i, "src") {
      "src"
    } else {
      i += 1
      continue
    }
    match attribute_value(html, i + name.length()) {
      Some((value, next)) => {
        if value.has_prefix("/") && !value.has_prefix("//") {
          found.push(value)
        }
        i = next
      }
      None => i += name.length()
    }
  }
  found
}

///|
/// The output file that serves the internal link `link`, relative to the output directory, or `None`
/// when the link leaves `base_path`: it does not start with it, or it has a `.` or `..` segment. The
/// fragment and the query are removed, and a directory link is served by its `index.html`.
pub fn link_file(base_path : String, link : String) -> String? {
  let path = match link.find("#") {
    Some(i) => link[:i].to_owned()
    None => link
  }
  let path = match path.find("?") {
    Some(i) => path[:i].to_owned()
    None => path
  }
  guard path.has_prefix(base_path) else { return None }
  let rel = path[base_path.length():].to_owned()
  if rel.split("/").any(segment => segment == "." || segment == "..") {
    return None
  }
  Some(if rel == "" || rel.has_suffix("/") { rel + "index.html" } else { rel })
}

///|
/// Whether the page `html` has a `<title>` element with text that is not only white space.
pub fn has_title(html : String) -> Bool {
  guard html.find("<title>") is Some(start) else { return false }
  let rest = html[start + "<title>".length():]
  guard rest.find("</title>") is Some(end) else { return false }
  rest[:end].trim() != ""
}

///|
/// The first problem of the XML document `xml`, or `None` when its tags are balanced. Declarations,
/// comments and empty-element tags do not open an element. This is the well-formed check of the
/// Atom feed, not a full XML parser.
pub fn xml_problem(xml : String) -> String? {
  let stack : Array[String] = []
  let mut rest = xml[:]
  while rest.find("<") is Some(start) {
    let tag = rest[start:]
    guard tag.find(">") is Some(end) else { return Some("`<` has no `>`") }
    let body = tag[1:end].to_owned()
    rest = tag[end + 1:]
    if body.has_prefix("?") || body.has_prefix("!") || body.has_suffix("/") {
      continue
    }
    let name = match body.find(" ") {
      Some(i) => body[:i].to_owned()
      None => body
    }
    if name.has_prefix("/") {
      let closing = name[1:].to_owned()
      match stack.pop() {
        Some(open) if open == closing => ()
        Some(open) => return Some("`</\{closing}>` closes `<\{open}>`")
        None => return Some("`</\{closing}>` has no start tag")
      }
    } else {
      stack.push(name)
    }
  }
  match stack.last() {
    Some(open) => Some("`<\{open}>` is not closed")
    None => None
  }
}

///|
/// The directory below the output directory that must stay empty: agent planning documents never go
/// on the site (design D15).
pub let forbidden_dir : String = "docs/superpowers/"
