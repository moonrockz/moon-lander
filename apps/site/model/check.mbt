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
/// Whether `text` is at `i` of `chars`. With `fold`, ASCII letters of `chars` match in any case;
/// `text` is then lower case.
fn chars_at(chars : Array[Char], i : Int, text : String, fold~ : Bool = false) -> Bool {
  let wanted = text.to_array()
  if i < 0 || i + wanted.length() > chars.length() {
    return false
  }
  for k, w in wanted {
    let c = chars[i + k]
    let c = if fold && c >= 'A' && c <= 'Z' {
      Int::unsafe_to_char(c.to_int() + 32)
    } else {
      c
    }
    if c != w {
      return false
    }
  }
  true
}

///|
/// The index of the first `text` in `chars` at or after `from`, or `None`.
fn chars_find(
  chars : Array[Char],
  from : Int,
  text : String,
  fold~ : Bool = false,
) -> Int? {
  for i in from.max(0)..<chars.length() {
    if chars_at(chars, i, text, fold~) {
      return Some(i)
    }
  }
  None
}

///|
fn is_char_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u{0C}'
}

///|
/// Whether the tag name `name` (lower case) starts at `i` of `chars`, after `<`, as a whole name.
fn tag_at(chars : Array[Char], i : Int, name : String) -> Bool {
  guard chars_at(chars, i, "<" + name, fold=true) else { return false }
  let after = i + 1 + name.length()
  after >= chars.length() ||
  is_char_space(chars[after]) ||
  chars[after] == '>' ||
  chars[after] == '/'
}

///|
/// Whether the page `html` has a `<title>` element with text that is not only white space. Tag names
/// match in any case and the start tag can have attributes. A title in a comment, a script or a
/// style element does not count.
pub fn has_title(html : String) -> Bool {
  let chars = html.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars_at(chars, i, "<!--") {
      match chars_find(chars, i + 4, "-->") {
        Some(end) => i = end + 3
        None => return false
      }
    } else if tag_at(chars, i, "script") || tag_at(chars, i, "style") {
      let name = if tag_at(chars, i, "script") { "script" } else { "style" }
      match chars_find(chars, i + 1, "</" + name, fold=true) {
        Some(end) => i = end + 2 + name.length()
        None => return false
      }
    } else if tag_at(chars, i, "title") {
      guard chars_find(chars, i, ">") is Some(open) else { return false }
      guard chars_find(chars, open + 1, "</title", fold=true) is Some(close) else {
        return false
      }
      return String::from_array(chars[open + 1:close]).trim() != ""
    } else {
      i += 1
    }
  }
  false
}

///|
fn is_name_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  c == '_' ||
  c == ':' ||
  c.to_int() > 127
}

///|
fn is_name_char(c : Char) -> Bool {
  is_name_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.'
}

///|
/// The XML name at `i` of `chars` and the index after it, or `None` when no name starts there.
fn xml_name(chars : Array[Char], i : Int) -> (String, Int)? {
  guard i < chars.length() && is_name_start(chars[i]) else { return None }
  let mut end = i + 1
  while end < chars.length() && is_name_char(chars[end]) {
    end += 1
  }
  Some((String::from_array(chars[i:end]), end))
}

///|
/// The index after the entity reference that starts with `&` at `i` of `chars`, or `None` when it is
/// not a character reference or one of the five predefined entities. An Atom feed has no DTD, so no
/// other entity is declared.
fn entity_end(chars : Array[Char], i : Int) -> Int? {
  guard chars_find(chars, i + 1, ";") is Some(semi) else { return None }
  let body = String::from_array(chars[i + 1:semi])
  let ok = if body.has_prefix("#x") {
    body.length() > 2 &&
    body[2:]
    .iter()
    .all(c => (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F'))
  } else if body.has_prefix("#") {
    body.length() > 1 && body[1:].iter().all(c => c >= '0' && c <= '9')
  } else {
    ["amp", "lt", "gt", "quot", "apos"].contains(body)
  }
  if ok {
    Some(semi + 1)
  } else {
    None
  }
}

///|
/// The first problem of the XML document `xml`, or `None` when it is well-formed for an Atom feed:
/// one root element, balanced tags with valid names, quoted attribute values without `<`, each `&`
/// a character reference or a predefined entity, and no text outside the root element. Declarations,
/// processing instructions, comments and CDATA sections are skipped. This is not a validating parser.
pub fn xml_problem(xml : String) -> String? {
  let chars = xml.to_array()
  let stack : Array[String] = []
  let mut roots = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '&' {
      guard entity_end(chars, i) is Some(end) else {
        return Some("`&` does not start an entity or character reference")
      }
      if stack.is_empty() {
        return Some("text is outside the root element")
      }
      i = end
    } else if c != '<' {
      if stack.is_empty() && !is_char_space(c) {
        return Some("text is outside the root element")
      }
      i += 1
    } else if chars_at(chars, i, "<?") {
      guard chars_find(chars, i + 2, "?>") is Some(end) else {
        return Some("`<?` has no `?>`")
      }
      i = end + 2
    } else if chars_at(chars, i, "<!--") {
      guard chars_find(chars, i + 4, "-->") is Some(end) else {
        return Some("a comment is not closed")
      }
      i = end + 3
    } else if chars_at(chars, i, "<![CDATA[") {
      if stack.is_empty() {
        return Some("a CDATA section is outside the root element")
      }
      guard chars_find(chars, i + 9, "]]>") is Some(end) else {
        return Some("a CDATA section is not closed")
      }
      i = end + 3
    } else if chars_at(chars, i, "<!") {
      guard chars_find(chars, i + 2, ">") is Some(end) else {
        return Some("`<` has no `>`")
      }
      i = end + 1
    } else if chars_at(chars, i, "</") {
      guard xml_name(chars, i + 2) is Some((closing, after)) else {
        return Some("an end tag has no valid name")
      }
      let mut j = after
      while j < chars.length() && is_char_space(chars[j]) {
        j += 1
      }
      guard j < chars.length() && chars[j] == '>' else {
        return Some("`<` has no `>`")
      }
      match stack.pop() {
        Some(open) if open == closing => ()
        Some(open) => return Some("`</\{closing}>` closes `<\{open}>`")
        None => return Some("`</\{closing}>` has no start tag")
      }
      i = j + 1
    } else {
      guard xml_name(chars, i + 1) is Some((name, after)) else {
        return Some("a start tag has no valid name")
      }
      if stack.is_empty() && roots > 0 {
        return Some("`<\{name}>` is a second root element")
      }
      let attributes : Array[String] = []
      let mut j = after
      let mut closed = false
      let mut empty = false
      while !closed {
        while j < chars.length() && is_char_space(chars[j]) {
          j += 1
        }
        guard j < chars.length() else { return Some("`<` has no `>`") }
        if chars[j] == '>' {
          closed = true
          j += 1
        } else if chars_at(chars, j, "/>") {
          closed = true
          empty = true
          j += 2
        } else {
          guard xml_name(chars, j) is Some((attribute, next)) else {
            return Some("`<\{name}>` has an attribute without a valid name")
          }
          if attributes.contains(attribute) {
            return Some("`<\{name}>` has the attribute `\{attribute}` twice")
          }
          attributes.push(attribute)
          j = next
          while j < chars.length() && is_char_space(chars[j]) {
            j += 1
          }
          guard j < chars.length() && chars[j] == '=' else {
            return Some("the attribute `\{attribute}` of `<\{name}>` has no value")
          }
          j += 1
          while j < chars.length() && is_char_space(chars[j]) {
            j += 1
          }
          guard j < chars.length() && (chars[j] == '"' || chars[j] == '\'') else {
            return Some("the value of `\{attribute}` in `<\{name}>` is not quoted")
          }
          let quote = chars[j]
          j += 1
          while j < chars.length() && chars[j] != quote {
            if chars[j] == '<' {
              return Some("the value of `\{attribute}` in `<\{name}>` has `<`")
            }
            if chars[j] == '&' {
              guard entity_end(chars, j) is Some(end) else {
                return Some(
                  "`&` does not start an entity or character reference",
                )
              }
              j = end
            } else {
              j += 1
            }
          }
          guard j < chars.length() else { return Some("`<` has no `>`") }
          j += 1
        }
      }
      if stack.is_empty() {
        roots += 1
      }
      if !empty {
        stack.push(name)
      }
      i = j
    }
  }
  match stack.last() {
    Some(open) => Some("`<\{open}>` is not closed")
    None => if roots == 0 { Some("there is no root element") } else { None }
  }
}

///|
/// The directory below the output directory that must stay empty: agent planning documents never go
/// on the site (design D15).
pub let forbidden_dir : String = "docs/superpowers/"
