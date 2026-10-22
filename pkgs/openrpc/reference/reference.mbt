///|
pub struct JsonPointer {
  priv parts : Array[String]
} derive(Debug)

///|
pub extend JsonPointer with @debug.Debug::{to_repr}

///|
/// Parse the plain RFC 6901 representation, without URI percent decoding.
pub fn JsonPointer::parse(
  text : String,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[JsonPointer, @json.Diagnostic] {
  if text.length() > limits.max_source() || limits.max_nodes() < 1 {
    return Err(
      @json.Diagnostic::new(
        @json.LimitExceeded,
        "JSON Pointer source/value limit exceeded",
      ),
    )
  }
  if text == "" {
    return Ok({ parts: [], })
  }
  if !text.has_prefix("/") {
    return Err(
      @json.Diagnostic::new(
        @json.InvalidReference,
        "JSON Pointer must start with a slash",
      ),
    )
  }
  let parts : Array[String] = []
  for raw in text[1:].split("/") {
    if parts.length() >= limits.max_depth() ||
      parts.length() >= limits.max_nodes() - 1 {
      return Err(
        @json.Diagnostic::new(
          @json.LimitExceeded,
          "JSON Pointer token limit exceeded",
        ),
      )
    }
    let token = raw.to_owned()
    let output = StringBuilder()
    let mut i = 0
    let mut start = 0
    while i < token.length() {
      let c = token.code_unit_at(i)
      if c == 126 {
        output.write_string(token[start:i].to_owned())
        if i + 1 >= token.length() {
          return Err(
            @json.Diagnostic::new(
              @json.InvalidReference,
              "Incomplete JSON Pointer escape",
            ),
          )
        }
        match token.code_unit_at(i + 1) {
          48 => output.write_string("~")
          49 => output.write_string("/")
          _ =>
            return Err(
              @json.Diagnostic::new(
                @json.InvalidReference,
                "Invalid JSON Pointer escape",
              ),
            )
        }
        i += 2
        start = i
      } else {
        i += 1
      }
    }
    output.write_string(token[start:].to_owned())
    parts.push(output.to_string())
  }
  Ok({ parts, })
}

///|
fn pointer_limits(
  parts : Array[String],
  limits : @json.Limits,
) -> Result[Unit, @json.Diagnostic] {
  if parts.length() > limits.max_depth() ||
    limits.max_nodes() < 1 ||
    parts.length() > limits.max_nodes() - 1 {
    return Err(
      @json.Diagnostic::new(
        @json.LimitExceeded,
        "JSON Pointer token limit exceeded",
      ),
    )
  }
  let mut remaining = limits.max_source()
  for token in parts {
    if remaining < 1 || token.length() > remaining - 1 {
      return Err(
        @json.Diagnostic::new(
          @json.LimitExceeded,
          "JSON Pointer text limit exceeded",
        ),
      )
    }
    remaining -= 1
    for c in token.code_units() {
      let count = if c == 126 || c == 47 { 2 } else { 1 }
      if count > remaining {
        return Err(
          @json.Diagnostic::new(
            @json.LimitExceeded,
            "JSON Pointer text limit exceeded",
          ),
        )
      }
      remaining -= count
    }
  }
  Ok(())
}

///|
pub fn JsonPointer::from_tokens(
  parts : Array[String],
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[JsonPointer, @json.Diagnostic] {
  match pointer_limits(parts, limits) {
    Ok(_) => Ok({ parts: parts.copy(), })
    Err(d) => Err(d)
  }
}

///|
pub fn JsonPointer::tokens(self : JsonPointer) -> Array[String] {
  self.parts.copy()
}

///|
pub fn JsonPointer::to_string(self : JsonPointer) -> String {
  let result = StringBuilder()
  for token in self.parts {
    result.write_string("/")
    result.write_string(
      token.replace(old="~", new="~0").replace(old="/", new="~1"),
    )
  }
  result.to_string()
}

///|
pub fn JsonPointer::resolve(
  self : JsonPointer,
  root : @json.Value,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[@json.Value, @json.Diagnostic] {
  if pointer_limits(self.parts, limits) is Err(d) {
    return Err(d)
  }
  let mut current = root
  let traversed : Array[String] = []
  for token in self.parts {
    traversed.push(token)
    let failure = fn() {
      @json.Diagnostic::new(
        @json.UnresolvedReference,
        "JSON Pointer target does not exist",
        path=traversed,
      )
    }
    if current.array_length() is Some(size) {
      if token.is_empty() || (token.length() > 1 && token.has_prefix("0")) {
        return Err(failure())
      }
      let mut index = 0
      for digit in token.code_units() {
        if digit < 48 || digit > 57 {
          return Err(failure())
        }
        let n = digit.to_int() - 48
        if index > (size - n) / 10 {
          return Err(failure())
        }
        index = index * 10 + n
        if index >= size {
          return Err(failure())
        }
      }
      current = current.array_item(index).unwrap()
    } else {
      match current.get(token) {
        Some(value) => current = value
        None => return Err(failure())
      }
    }
  }
  Ok(current)
}

///|
pub struct Reference {
  uri : UriReference
  fragment : ReferenceFragment
} derive(Debug)

///|
pub extend Reference with @debug.Debug::{to_repr}

///|
pub enum ReferenceFragment {
  WholeResource
  PointerFragment(JsonPointer)
  IdentifierFragment(String)
} derive(Debug)

///|
pub extend ReferenceFragment with @debug.Debug::{to_repr}

///|
fn hex(c : UInt16) -> Int32? {
  if c >= 48 && c <= 57 {
    Some(c.to_int() - 48)
  } else if c >= 65 && c <= 70 {
    Some(c.to_int() - 55)
  } else if c >= 97 && c <= 102 {
    Some(c.to_int() - 87)
  } else {
    None
  }
}

///|
fn fragment_decode(text : String) -> Result[String, @json.Diagnostic] {
  let bytes : Array[Byte] = []
  let encoded = @utf8.encode(text[:])
  let mut i = 0
  while i < encoded.length() {
    if encoded[i] == 37 {
      if i + 2 >= encoded.length() {
        return Err(
          @json.Diagnostic::new(
            @json.InvalidReference,
            "Incomplete URI percent escape",
          ),
        )
      }
      match
        (
          hex(encoded[i + 1].to_int().to_uint16()),
          hex(encoded[i + 2].to_int().to_uint16()),
        ) {
        (Some(a), Some(b)) => bytes.push((a * 16 + b).to_byte())
        _ =>
          return Err(
            @json.Diagnostic::new(
              @json.InvalidReference,
              "Invalid URI percent escape",
            ),
          )
      }
      i += 3
    } else {
      bytes.push(encoded[i])
      i += 1
    }
  }
  Ok(@utf8.decode(Bytes::from_array(bytes)[:], ignore_bom=false)) catch {
    _ =>
      Err(
        @json.Diagnostic::new(
          @json.InvalidReference,
          "URI fragment is not UTF-8",
        ),
      )
  }
}

///|
/// Checked JSON-target reference; reading performs no resolution or fetching.
pub fn Reference::parse(
  text : String,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Reference, @json.Diagnostic] {
  match UriReference::parse(text, limits~) {
    Ok(uri) => Reference::from_uri(uri, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn Reference::from_uri(
  uri : UriReference,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Reference, @json.Diagnostic] {
  if uri.raw.length() > limits.max_source() || limits.max_nodes() < 1 {
    return Err(
      @json.Diagnostic::new(
        @json.LimitExceeded,
        "JSON reference source/value limit exceeded",
      ),
    )
  }
  let fragment = match uri.fragment {
    None => WholeResource
    Some(raw) => {
      let decoded = match fragment_decode(raw) {
        Ok(text) => text
        Err(d) => return Err(d)
      }
      if decoded.is_empty() {
        WholeResource
      } else if decoded.has_prefix("/") {
        match JsonPointer::parse(decoded, limits~) {
          Ok(pointer) => PointerFragment(pointer)
          Err(d) => return Err(d)
        }
      } else {
        IdentifierFragment(decoded)
      }
    }
  }
  Ok({ uri, fragment, })
}

///|
pub fn Reference::text(self : Reference) -> String {
  self.uri.raw
}

///|
pub fn Reference::uri(self : Reference) -> UriReference {
  self.uri
}

///|
pub fn Reference::fragment(self : Reference) -> ReferenceFragment {
  self.fragment
}

///|
pub fn Reference::local_pointer(self : Reference) -> JsonPointer? {
  if self.uri.scheme is Some(_) ||
    self.uri.authority is Some(_) ||
    !self.uri.path.is_empty() ||
    self.uri.query is Some(_) {
    return None
  }
  match self.fragment {
    WholeResource => Some({ parts: [], })
    PointerFragment(pointer) => Some(pointer)
    IdentifierFragment(_) => None
  }
}

///|
pub fn Reference::resolve(
  self : Reference,
  base : UriReference,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Reference, @json.Diagnostic] {
  match self.uri.resolve(base, limits~) {
    Ok(uri) => Reference::from_uri(uri, limits~)
    Err(d) => Err(d)
  }
}
