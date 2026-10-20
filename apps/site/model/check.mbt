///|
/// The `href` values, then the `src` values, in `html` that start with `/`. A value that starts with
/// `//` is a link to another host, so it is not included.
pub fn internal_links(html : String) -> Array[String] {
  let found = []
  for attr in ["href=\"", "src=\""] {
    let mut rest = html[:]
    while rest.find(attr) is Some(at) {
      let value_start = rest[at + attr.length():]
      guard value_start.find("\"") is Some(end) else { break }
      let value = value_start[:end].to_owned()
      if value.has_prefix("/") && !value.has_prefix("//") {
        found.push(value)
      }
      rest = value_start[end + 1:]
    }
  }
  found
}

///|
/// The output file that serves the internal link `link`, relative to the output directory, or `None`
/// when the link does not start with `base_path`. The fragment and the query are removed, and a
/// directory link is served by its `index.html`.
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
  Some(if rel == "" || rel.has_suffix("/") { rel + "index.html" } else { rel })
}
