///|
fn uri_render(
  scheme : String?,
  authority : String?,
  path : String,
  query : String?,
  fragment : String?,
) -> String {
  let out = StringBuilder()
  if scheme is Some(scheme) {
    out.write_string(scheme)
    out.write_string(":")
  }
  if authority is Some(authority) {
    out.write_string("//")
    out.write_string(authority)
  }
  out.write_string(path)
  if query is Some(query) {
    out.write_string("?")
    out.write_string(query)
  }
  if fragment is Some(fragment) {
    out.write_string("#")
    out.write_string(fragment)
  }
  out.to_string()
}

///|
pub fn UriReference::without_fragment(self : UriReference) -> UriReference {
  if self.fragment is None {
    return self
  }
  let raw = self.raw[:self.raw.find("#").unwrap()].to_owned()
  { ..self, raw, fragment: None, }
}

///|
fn remove_dot_segments(path : String) -> String {
  let output : Array[UInt16] = []
  let mut at = 0
  let remove_last = fn() {
    while !output.is_empty() && output[output.length() - 1] != 47 {
      ignore(output.pop())
    }
    if !output.is_empty() {
      ignore(output.pop())
    }
  }
  while at < path.length() {
    let rest = path[at:]
    if rest.has_prefix("../") {
      at += 3
    } else if rest.has_prefix("./") {
      at += 2
    } else if rest.has_prefix("/./") {
      at += 2
    } else if rest == "/." {
      output.push(47)
      at = path.length()
    } else if rest.has_prefix("/../") {
      at += 3
      remove_last()
    } else if rest == "/.." {
      remove_last()
      output.push(47)
      at = path.length()
    } else if rest == "." || rest == ".." {
      at = path.length()
    } else {
      let mut end = at
      if path.code_unit_at(end) == 47 {
        end += 1
      }
      while end < path.length() && path.code_unit_at(end) != 47 {
        end += 1
      }
      for i in at..<end {
        output.push(path.code_unit_at(i))
      }
      at = end
    }
  }
  let out = StringBuilder()
  for c in output {
    out.write_char(c.to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
fn uri_render_checked(
  scheme : String?,
  authority : Authority?,
  path : String,
  query : String?,
  fragment : String?,
  limit : Int32,
) -> UriReference raise UriRead {
  let mut remaining = limit
  let charge = fn(text : String, punctuation : Int32) raise UriRead {
    if punctuation > remaining || text.length() > remaining - punctuation {
      uri_limit("Resolved URI size limit exceeded")
    }
    remaining -= punctuation + text.length()
  }
  if scheme is Some(scheme) {
    charge(scheme, 1)
  }
  if authority is Some(authority) {
    charge(authority.raw, 2)
  }
  charge(path, 0)
  if query is Some(query) {
    charge(query, 1)
  }
  if fragment is Some(fragment) {
    charge(fragment, 1)
  }
  let raw = uri_render(scheme, authority.map(a => a.raw), path, query, fragment)
  { raw, scheme, authority, path, query, fragment, }
}

///|
/// Strict RFC3986 section5.2 resolution. Neither value's original text changes.
pub fn UriReference::resolve(
  self : UriReference,
  base : UriReference,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[UriReference, @json.Diagnostic] {
  try {
    if !base.is_absolute() {
      uri_invalid("URI resolution requires an absolute base")
    }
    if self.raw.length() > limits.max_source() ||
      base.raw.length() > limits.max_source() {
      uri_limit("URI resolution input size limit exceeded")
    }
    let (scheme, authority, path, query) = if self.scheme is Some(_) {
      (self.scheme, self.authority, remove_dot_segments(self.path), self.query)
    } else if self.authority is Some(_) {
      (base.scheme, self.authority, remove_dot_segments(self.path), self.query)
    } else if self.path.is_empty() {
      (
        base.scheme,
        base.authority,
        base.path,
        if self.query is Some(_) {
          self.query
        } else {
          base.query
        },
      )
    } else {
      let path = if self.path.has_prefix("/") {
        remove_dot_segments(self.path)
      } else {
        let prefix = if base.authority is Some(_) && base.path.is_empty() {
          "/"
        } else if base.path.rev_find("/") is Some(slash) {
          base.path[:slash + 1].to_owned()
        } else {
          ""
        }
        if prefix.length() > limits.max_source() - self.path.length() {
          uri_limit("Merged URI path size limit exceeded")
        }
        remove_dot_segments(prefix + self.path)
      }
      (base.scheme, base.authority, path, self.query)
    }
    Ok(
      uri_render_checked(
        scheme,
        authority,
        path,
        query,
        self.fragment,
        limits.max_source(),
      ),
    )
  } catch {
    UriRead(d) => Err(d)
  }
}

///|
fn normalize_percent(text : String, fold~ : Bool = false) -> String {
  let out = StringBuilder()
  let mut at = 0
  let lower = fn(c : UInt16) {
    if fold && c >= 65 && c <= 90 {
      c + 32
    } else {
      c
    }
  }
  let digits = "0123456789ABCDEF"
  while at < text.length() {
    let c = text.code_unit_at(at)
    if c == 37 {
      let value = hex(text.code_unit_at(at + 1)).unwrap() * 16 +
        hex(text.code_unit_at(at + 2)).unwrap()
      if uri_unreserved(value.to_uint16()) {
        out.write_char(lower(value.to_uint16()).to_int().unsafe_to_char())
      } else {
        out.write_string("%")
        out.write_char(
          digits.code_unit_at(value / 16).to_int().unsafe_to_char(),
        )
        out.write_char(
          digits.code_unit_at(value % 16).to_int().unsafe_to_char(),
        )
      }
      at += 3
    } else {
      out.write_char(lower(c).to_int().unsafe_to_char())
      at += 1
    }
  }
  out.to_string()
}

///|
fn Authority::identity(self : Authority) -> String {
  let out = StringBuilder()
  if self.userinfo is Some(user) {
    out.write_string(normalize_percent(user))
    out.write_string("@")
  }
  match self.host {
    RegisteredName(name) => out.write_string(normalize_percent(name, fold=true))
    Ipv4(address) => out.write_string(address)
    Ipv6(address) | IpvFuture(address) => {
      out.write_string("[")
      out.write_string(address.to_lower())
      out.write_string("]")
    }
  }
  if self.port is Some(port) {
    out.write_string(":")
    out.write_string(port)
  }
  out.to_string()
}

///|
/// Syntax-based identity. Relative rootless dot segments need a base first.
pub fn UriReference::identity(self : UriReference) -> String {
  let path = normalize_percent(self.path)
  let path = if self.is_absolute() ||
    self.authority is Some(_) ||
    path.has_prefix("/") {
    remove_dot_segments(path)
  } else {
    path
  }
  uri_render(
    self.scheme.map(s => s.to_lower()),
    self.authority.map(a => a.identity()),
    path,
    self.query.map(q => normalize_percent(q)),
    self.fragment.map(f => normalize_percent(f)),
  )
}
