///|
/// An SCT list that cannot be read.
pub suberror SctError {
  BadSct(String)
} derive(Debug)

///|
pub extend SctError with @debug.Debug::{to_repr}

///|
/// One RFC 6962 v1 signed certificate timestamp.
pub struct Sct {
  log_id : Bytes
  /// Milliseconds since 1970.
  timestamp : Int64
  extensions : Bytes
  /// The TLS hash and signature algorithm codes.
  hash_algorithm : Int
  signature_algorithm : Int
  signature : Bytes
}

///|
priv struct Cursor {
  bytes : BytesView
  mut at : Int
}

///|
fn Cursor::take(self : Cursor, count : Int) -> BytesView raise SctError {
  guard count >= 0 && self.at + count <= self.bytes.length() else {
    raise BadSct("truncated")
  }
  let part = self.bytes[self.at:self.at + count]
  self.at += count
  part
}

///|
fn Cursor::number(self : Cursor, size : Int) -> Int64 raise SctError {
  let mut value = 0L
  for byte in self.take(size) {
    value = (value << 8) | byte.to_int64()
  }
  value
}

///|
fn Cursor::vector(self : Cursor, size : Int) -> BytesView raise SctError {
  let length = self.number(size).to_int()
  self.take(length)
}

///|
/// Read the SCT list of a certificate's `1.3.6.1.4.1.11129.2.4.2` extension
/// value: a DER OCTET STRING that holds a TLS SignedCertificateTimestampList.
pub fn parse_list(extension_value : BytesView) -> Array[Sct] raise SctError {
  let list = @der.parse_tag(extension_value, @der.OCTET_STRING) catch {
    _ => raise BadSct("the extension is not an OCTET STRING")
  }
  let outer = { bytes: list.content, at: 0 }
  let entries = { bytes: outer.vector(2), at: 0 }
  guard outer.at == outer.bytes.length() else { raise BadSct("trailing bytes") }
  let scts = []
  while entries.at < entries.bytes.length() {
    let item = { bytes: entries.vector(2), at: 0 }
    guard item.number(1) == 0L else { raise BadSct("not a v1 SCT") }
    let log_id = item.take(32).to_owned()
    let timestamp = item.number(8)
    let extensions = item.vector(2).to_owned()
    let hash_algorithm = item.number(1).to_int()
    let signature_algorithm = item.number(1).to_int()
    let signature = item.vector(2).to_owned()
    guard item.at == item.bytes.length() else { raise BadSct("trailing bytes in an SCT") }
    scts.push({
      log_id,
      timestamp,
      extensions,
      hash_algorithm,
      signature_algorithm,
      signature,
    })
  }
  scts
}

///|
fn push_number(out : Array[Byte], value : Int64, size : Int) -> Unit {
  for i in 0..<size {
    out.push(((value >> ((size - 1 - i) * 8)) & 0xffL).to_byte())
  }
}

///|
/// The data that a CT log signs for a precertificate entry (RFC 6962,
/// section 3.2): the timestamp, the SHA-256 of the issuer key and the leaf
/// TBSCertificate without the SCT list.
pub fn Sct::signed_data(
  self : Sct,
  issuer_spki : BytesView,
  precertificate_tbs : BytesView,
) -> Bytes {
  let out : Array[Byte] = [b'\x00', b'\x00']
  push_number(out, self.timestamp, 8)
  push_number(out, 1L, 2)
  for byte in @signature.sha256(issuer_spki) {
    out.push(byte)
  }
  push_number(out, precertificate_tbs.length().to_int64(), 3)
  for byte in precertificate_tbs {
    out.push(byte)
  }
  push_number(out, self.extensions.length().to_int64(), 2)
  for byte in self.extensions {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// True when the SCT is an ECDSA SHA-256 signature by `key` over the
/// precertificate data.
pub fn Sct::verify(
  self : Sct,
  key : @signature.PublicKey,
  issuer_spki : BytesView,
  precertificate_tbs : BytesView,
) -> Bool {
  // TLS codes: hash sha256 = 4, signature ecdsa = 3.
  guard self.hash_algorithm == 4 && self.signature_algorithm == 3 else { return false }
  key.verify(
    self.signed_data(issuer_spki, precertificate_tbs),
    self.signature,
    hash=Sha256,
  )
}
