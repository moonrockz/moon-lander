///|
/// A hash function of the SHA-2 family.
pub(all) enum HashAlgorithm {
  Sha256
  Sha384
  Sha512
} derive(Eq, Debug)

///|
pub extend HashAlgorithm with Eq::{equal, not_equal}

///|
pub extend HashAlgorithm with @debug.Debug::{to_repr}

///|
/// The digest of `bytes` with `algorithm`.
pub fn digest(algorithm : HashAlgorithm, bytes : BytesView) -> Bytes {
  let kind : @sha2.Kind = match algorithm {
    Sha256 => Sha256
    Sha384 => Sha384
    Sha512 => Sha512
  }
  @sha2.hash(bytes, kind~)
}

///|
/// The SHA-256 digest of `bytes`.
pub fn sha256(bytes : BytesView) -> Bytes {
  digest(Sha256, bytes)
}

///|
/// A public key type that the verifier knows.
pub enum KeyKind {
  EcdsaP256
  EcdsaP384
} derive(Eq, Debug)

///|
pub extend KeyKind with Eq::{equal, not_equal}

///|
pub extend KeyKind with @debug.Debug::{to_repr}

///|
/// The hash that Sigstore uses with a key of this kind.
pub fn KeyKind::hash(self : KeyKind) -> HashAlgorithm {
  match self {
    EcdsaP256 => Sha256
    EcdsaP384 => Sha384
  }
}

///|
/// A key that cannot be used.
pub suberror KeyError {
  /// The key is valid, but of a type that the verifier does not support, for
  /// example Ed25519 or RSA. The text names the type.
  UnsupportedKey(String)
  /// The key bytes break the rule that the text names.
  BadKey(String)
} derive(Debug)

///|
pub extend KeyError with @debug.Debug::{to_repr}

///|
pub fn KeyError::message(self : KeyError) -> String {
  match self {
    UnsupportedKey(kind) => "unsupported key type \{kind}"
    BadKey(rule) => "bad public key: \{rule}"
  }
}

///|
/// An ECDSA public key read from a DER SubjectPublicKeyInfo.
pub struct PublicKey {
  kind : KeyKind
  /// The DER SubjectPublicKeyInfo.
  spki : Bytes
  priv point : Bytes
}

///|
/// The field primes, big-endian.
let p256_prime : String = "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"

///|
let p384_prime : String = "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff"

///|
fn KeyKind::size(self : KeyKind) -> Int {
  match self {
    EcdsaP256 => 32
    EcdsaP384 => 48
  }
}

///|
fn KeyKind::curve(self : KeyKind) -> @curve.Curve {
  match self {
    EcdsaP256 => P256
    EcdsaP384 => P384
  }
}

///|
fn KeyKind::prime(self : KeyKind) -> Bytes {
  let text = match self {
    EcdsaP256 => p256_prime
    EcdsaP384 => p384_prime
  }
  @encoding.decode_hex(text) catch {
    _ => abort("bad prime constant")
  }
}

///|
/// True when the big-endian `a` is less than the big-endian `b` of the same length.
fn less_than(a : BytesView, b : BytesView) -> Bool {
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return a[i] < b[i]
    }
  }
  false
}

///|
/// Read a public key from a DER SubjectPublicKeyInfo. Only uncompressed points
/// whose coordinates are less than the field prime and that are on the curve
/// are accepted.
pub fn PublicKey::from_spki(spki : BytesView) -> PublicKey raise KeyError {
  let (algorithm, parameters, point) = read_spki(spki) catch {
    err => raise BadKey(err.message())
  }
  let kind = match algorithm {
    "1.2.840.10045.2.1" =>
      match parameters {
        Some("1.2.840.10045.3.1.7") => EcdsaP256
        Some("1.3.132.0.34") => EcdsaP384
        Some(other) => raise UnsupportedKey("ECDSA curve \{other}")
        None => raise BadKey("ECDSA key without a named curve")
      }
    "1.3.101.112" => raise UnsupportedKey("Ed25519")
    "1.2.840.113549.1.1.1" => raise UnsupportedKey("RSA")
    other => raise UnsupportedKey(other)
  }
  let size = kind.size()
  guard point.length() == 1 + 2 * size && point[0] == b'\x04' else {
    raise BadKey("the point is not an uncompressed point of the curve")
  }
  let prime = kind.prime()
  guard less_than(point[1:1 + size], prime) &&
    less_than(point[1 + size:], prime) else {
    raise BadKey("a coordinate is not less than the field prime")
  }
  ignore(
    @ecdsa.PublicKey::new(aligned_point(point), curve=kind.curve()) catch {
      _ => raise BadKey("the point is not on the curve")
    },
  )
  { kind, spki: spki.to_owned(), point: point.to_owned() }
}

///|
fn read_spki(spki : BytesView) -> (String, String?, BytesView) raise @der.DerError {
  let outer = @der.parse_tag(spki, @der.SEQUENCE).children()
  let algorithm = outer.expect(@der.SEQUENCE).children()
  let oid = algorithm.expect(@der.OID).oid()
  let parameters = match algorithm.peek_tag() {
    Some(tag) if tag == @der.OID => Some(algorithm.next().oid())
    Some(tag) if tag == @der.NULL => {
      ignore(algorithm.next())
      None
    }
    Some(_) => raise @der.Malformed("unknown key parameters")
    None => None
  }
  algorithm.finish()
  let point = outer.expect(@der.BIT_STRING).bit_string_bytes()
  outer.finish()
  (oid, parameters, point)
}

///|
/// A hash that returns its input, so mooncrypt verifies a digest that the
/// caller computed.
priv struct Prehashed {
  bytes : Array[Byte]
  size : Int
}

///|
impl @spec.Hash for Prehashed with write(self, data) {
  for byte in data {
    self.bytes.push(byte)
  }
}

///|
impl @spec.Hash for Prehashed with finish(self) {
  Bytes::from_array(self.bytes)
}

///|
impl @spec.Hash for Prehashed with reset(self) {
  self.bytes.clear()
}

///|
impl @spec.Hash for Prehashed with size(self) {
  self.size
}

///|
impl @spec.Hash for Prehashed with block(_self) {
  128
}

///|
/// Read a strict DER ECDSA-Sig-Value into the fixed-width form `r ∥ s`, or
/// `None` when it is not strict DER or a value is wider than `size` bytes.
pub fn der_signature_to_raw(signature : BytesView, size : Int) -> Bytes? {
  let parts = try {
    let reader = @der.parse_tag(signature, @der.SEQUENCE).children()
    let r = reader.expect(@der.INTEGER).unsigned()
    let s = reader.expect(@der.INTEGER).unsigned()
    reader.finish()
    (r, s)
  } catch {
    _ => return None
  }
  let (r, s) = parts
  guard r.length() <= size && s.length() <= size else { return None }
  let out = FixedArray::make(2 * size, b'\x00')
  for i in 0..<r.length() {
    out[size - r.length() + i] = r[i]
  }
  for i in 0..<s.length() {
    out[2 * size - s.length() + i] = s[i]
  }
  Some(Bytes::from_array(out))
}

///|
/// A copy of `point` that starts 7 bytes into a new buffer, so that the
/// coordinates after the 0x04 prefix start on an 8-byte boundary.
///
/// mooncrypt reads the coordinates with `BigInt::from_octets(point[1:...])`,
/// and core reads big-endian 64-bit words with one load each. On native, a new
/// buffer starts on an 8-byte boundary (after the 8-byte object header), so
/// without this offset every load is misaligned. That is undefined behavior in
/// C, and the zig (UBSan) native build aborts on it. Remove this when core reads
/// unaligned words safely.
fn aligned_point(point : BytesView) -> BytesView {
  let buffer = FixedArray::make(7 + point.length(), b'\x00')
  for i in 0..<point.length() {
    buffer[7 + i] = point[i]
  }
  Bytes::from_array(buffer)[7:]
}

///|
/// A copy of `bytes` in a new buffer, which starts on an 8-byte boundary, for
/// the same reason as `aligned_point`.
fn owned(bytes : BytesView) -> Bytes {
  bytes.to_owned()
}

///|
/// Verify a fixed-width `r ∥ s` signature over a digest that the caller made.
pub fn PublicKey::verify_digest_raw(
  self : PublicKey,
  digest : BytesView,
  signature : BytesView,
) -> Bool {
  let size = digest.length()
  let key = @ecdsa.PublicKey::with_hash(
    aligned_point(self.point),
    () => ({ bytes: [], size } : Prehashed),
    curve=self.kind.curve(),
  ) catch {
    _ => return false
  }
  @spec.Verifier::verify(key, owned(digest), owned(signature))
}

///|
/// Verify a DER signature over a digest that the caller made.
pub fn PublicKey::verify_digest(
  self : PublicKey,
  digest : BytesView,
  signature : BytesView,
) -> Bool {
  guard der_signature_to_raw(signature, self.kind.size()) is Some(raw) else {
    return false
  }
  self.verify_digest_raw(digest, raw)
}

///|
/// Verify a DER signature over `message`, hashed with `hash` (by default the
/// hash of the key kind).
pub fn PublicKey::verify(
  self : PublicKey,
  message : BytesView,
  signature : BytesView,
  hash? : HashAlgorithm,
) -> Bool {
  let algorithm = hash.unwrap_or(self.kind.hash())
  self.verify_digest(digest(algorithm, message), signature)
}
