///|
// Percent triplets are checked once before component grammar checks.
fn uri_component(text : StringView, kind : Int32) -> Bool {
  let mut at = 0
  while at < text.length() {
    let c = text.code_unit_at(at)
    let valid = if c == 37 {
      at += 3
      continue
    } else if kind == 0 {
      uri_unreserved(c) || uri_subdelimiter(c)
    } else if kind == 1 {
      uri_unreserved(c) || uri_subdelimiter(c) || c == 58
    } else if kind == 2 {
      uri_pchar(c) || c == 47
    } else {
      uri_pchar(c) || c == 47 || c == 63
    }
    if !valid {
      return false
    }
    at += 1
  }
  true
}

///|
fn valid_ipv4(text : StringView) -> Bool {
  if text.length() > 15 {
    return false
  }
  let parts = text.split(".").collect()
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    if part.is_empty() ||
      part.length() > 3 ||
      (part.length() > 1 && part.code_unit_at(0) == 48) {
      return false
    }
    let mut number = 0
    for c in part.code_units() {
      if !uri_digit(c) {
        return false
      }
      number = number * 10 + c.to_int() - 48
    }
    if number > 255 {
      return false
    }
  }
  true
}

///|
fn ipv6_groups(text : StringView, ipv4_last : Bool) -> Int32? {
  if text.is_empty() {
    return Some(0)
  }
  let groups = text.split(":").collect()
  if groups.length() > 8 {
    return None
  }
  let mut count = 0
  for i, group in groups {
    if ipv4_last && i == groups.length() - 1 && group.contains(".") {
      if !valid_ipv4(group) {
        return None
      }
      count += 2
    } else {
      if group.is_empty() || group.length() > 4 {
        return None
      }
      for c in group.code_units() {
        if hex(c) is None {
          return None
        }
      }
      count += 1
    }
  }
  Some(count)
}

///|
fn valid_ipv6(text : StringView) -> Bool {
  if text.length() > 45 {
    return false
  }
  let parts = text.split("::").collect()
  if parts.length() == 1 {
    return ipv6_groups(text, true) == Some(8)
  }
  if parts.length() != 2 {
    return false
  }
  match (ipv6_groups(parts[0], false), ipv6_groups(parts[1], true)) {
    (Some(a), Some(b)) => a + b < 8
    _ => false
  }
}

///|
fn valid_ipvfuture(text : StringView) -> Bool {
  guard text.length() > 3 &&
    (text.code_unit_at(0) == 118 || text.code_unit_at(0) == 86) else {
    return false
  }
  guard text.find(".") is Some(dot) && dot > 1 && dot < text.length() - 1 else {
    return false
  }
  for i in 1..<dot {
    if hex(text.code_unit_at(i)) is None {
      return false
    }
  }
  for i in (dot + 1)..<text.length() {
    let c = text.code_unit_at(i)
    if !uri_unreserved(c) && !uri_subdelimiter(c) && c != 58 {
      return false
    }
  }
  true
}

///|
fn read_authority(text : StringView) -> Authority raise UriRead {
  let raw = text.to_owned()
  let mut rest = text
  let userinfo = if text.find("@") is Some(at) {
    let user = text[:at]
    if !uri_component(user, 1) {
      uri_invalid("Invalid URI user information")
    }
    rest = text[at + 1:]
    Some(user.to_owned())
  } else {
    None
  }
  let (host, port) = if rest.has_prefix("[") {
    guard rest.find("]") is Some(end) else {
      uri_invalid("Unclosed URI IP literal")
    }
    let address = rest[1:end]
    let host = if valid_ipv6(address) {
      Ipv6(address.to_owned())
    } else if valid_ipvfuture(address) {
      IpvFuture(address.to_owned())
    } else {
      uri_invalid("Invalid URI IP literal")
    }
    let suffix = rest[end + 1:]
    let port = if suffix.is_empty() {
      None
    } else if suffix.has_prefix(":") {
      Some(suffix[1:].to_owned())
    } else {
      uri_invalid("Unexpected text after URI IP literal")
    }
    (host, port)
  } else {
    let (name, port) = if rest.find(":") is Some(colon) {
      (rest[:colon], Some(rest[colon + 1:].to_owned()))
    } else {
      (rest, None)
    }
    if !uri_component(name, 0) {
      uri_invalid("Invalid URI registered host name")
    }
    let host = if valid_ipv4(name) {
      Ipv4(name.to_owned())
    } else {
      RegisteredName(name.to_owned())
    }
    (host, port)
  }
  if port is Some(port) {
    for c in port.code_units() {
      if !uri_digit(c) {
        uri_invalid("URI port must contain only digits")
      }
    }
  }
  { raw, userinfo, host, port, }
}

///|
fn read_uri(text : String) -> UriReference raise UriRead {
  let mut at = 0
  while at < text.length() {
    let c = text.code_unit_at(at)
    if c <= 32 || c >= 127 {
      uri_invalid("URI references require ASCII URI characters")
    }
    if c == 37 {
      if text.length() - at < 3 ||
        hex(text.code_unit_at(at + 1)) is None ||
        hex(text.code_unit_at(at + 2)) is None {
        uri_invalid("Invalid URI percent escape")
      }
      at += 2
    }
    at += 1
  }
  let mut hierarchy = text[:]
  let fragment = if text.find("#") is Some(hash) {
    hierarchy = text[:hash]
    let fragment = text[hash + 1:]
    if !uri_component(fragment, 3) {
      uri_invalid("Invalid URI fragment character")
    }
    Some(fragment.to_owned())
  } else {
    None
  }
  let query = if hierarchy.find("?") is Some(question) {
    let query = hierarchy[question + 1:]
    if !uri_component(query, 3) {
      uri_invalid("Invalid URI query character")
    }
    hierarchy = hierarchy[:question]
    Some(query.to_owned())
  } else {
    None
  }
  let scheme = if hierarchy.find(":") is Some(colon) &&
    (hierarchy.find("/") is None || colon < hierarchy.find("/").unwrap()) {
    if colon == 0 {
      uri_invalid("URI scheme must start with a letter")
    }
    for i in 0..<colon {
      let c = hierarchy.code_unit_at(i)
      if !uri_letter(c) &&
        (i == 0 || (!uri_digit(c) && c != 43 && c != 45 && c != 46)) {
        uri_invalid("Invalid URI scheme")
      }
    }
    let name = hierarchy[:colon].to_owned()
    hierarchy = hierarchy[colon + 1:]
    Some(name)
  } else {
    None
  }
  let authority = if hierarchy.has_prefix("//") {
    let rest = hierarchy[2:]
    let end = rest.find("/").unwrap_or(rest.length())
    let authority = read_authority(rest[:end])
    hierarchy = rest[end:]
    Some(authority)
  } else {
    None
  }
  if !uri_component(hierarchy, 2) {
    uri_invalid("Invalid URI path character")
  }
  { raw: text, scheme, authority, path: hierarchy.to_owned(), query, fragment, }
}

///|
pub fn UriReference::parse(
  text : String,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[UriReference, @json.Diagnostic] {
  if text.length() > limits.max_source() {
    return Err(
      @json.Diagnostic::new(@json.LimitExceeded, "URI source limit exceeded"),
    )
  }
  if limits.max_nodes() < 1 {
    return Err(
      @json.Diagnostic::new(@json.LimitExceeded, "URI value limit exceeded"),
    )
  }
  Ok(read_uri(text)) catch {
    UriRead(d) => Err(d)
  }
}
