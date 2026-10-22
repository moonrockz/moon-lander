///|
/// Checked generic RFC3986 URI-reference components, with original spelling.
pub struct UriReference {
  raw : String
  scheme : String?
  authority : Authority?
  path : String
  query : String?
  fragment : String?
} derive(Debug)

///|
pub extend UriReference with @debug.Debug::{to_repr}

///|
pub struct Authority {
  raw : String
  userinfo : String?
  host : Host
  port : String?
} derive(Debug)

///|
pub extend Authority with @debug.Debug::{to_repr}

///|
pub enum Host {
  RegisteredName(String)
  Ipv4(String)
  Ipv6(String)
  IpvFuture(String)
} derive(Debug)

///|
pub extend Host with @debug.Debug::{to_repr}

///|
pub fn UriReference::text(self : UriReference) -> String {
  self.raw
}

///|
pub fn UriReference::scheme(self : UriReference) -> String? {
  self.scheme
}

///|
pub fn UriReference::authority(self : UriReference) -> Authority? {
  self.authority
}

///|
pub fn UriReference::path(self : UriReference) -> String {
  self.path
}

///|
pub fn UriReference::query(self : UriReference) -> String? {
  self.query
}

///|
/// Encoded fragment text, preserving absent versus present-empty.
pub fn UriReference::fragment(self : UriReference) -> String? {
  self.fragment
}

///|
pub fn UriReference::is_absolute(self : UriReference) -> Bool {
  self.scheme is Some(_)
}

///|
pub fn Authority::text(self : Authority) -> String {
  self.raw
}

///|
pub fn Authority::userinfo(self : Authority) -> String? {
  self.userinfo
}

///|
pub fn Authority::host(self : Authority) -> Host {
  self.host
}

///|
/// Port is an exact digit token. Generic URI syntax imposes no transport range.
pub fn Authority::port(self : Authority) -> String? {
  self.port
}

///|
priv suberror UriRead {
  UriRead(@json.Diagnostic)
} derive(Debug)

///|
fn[T] uri_invalid(message : String) -> T raise UriRead {
  raise UriRead(@json.Diagnostic::new(@json.InvalidReference, message))
}

///|
fn[T] uri_limit(message : String) -> T raise UriRead {
  raise UriRead(@json.Diagnostic::new(@json.LimitExceeded, message))
}

///|
fn uri_letter(c : UInt16) -> Bool {
  (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
}

///|
fn uri_digit(c : UInt16) -> Bool {
  c >= 48 && c <= 57
}

///|
fn uri_unreserved(c : UInt16) -> Bool {
  uri_letter(c) || uri_digit(c) || c == 45 || c == 46 || c == 95 || c == 126
}

///|
fn uri_subdelimiter(c : UInt16) -> Bool {
  match c.to_int() {
    33 | 36 | 38 | 39 | 40 | 41 | 42 | 43 | 44 | 59 | 61 => true
    _ => false
  }
}

///|
fn uri_pchar(c : UInt16) -> Bool {
  uri_unreserved(c) || uri_subdelimiter(c) || c == 58 || c == 64
}
