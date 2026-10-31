///|
/// An RFC 3161 timestamp that cannot be used.
pub(all) suberror TimestampError {
  /// The token breaks the rule that the text names.
  BadTimestamp(String)
  /// The token is valid but uses an algorithm that the verifier does not
  /// support; the text names it.
  UnsupportedTimestamp(String)
} derive(Debug)

///|
pub extend TimestampError with @debug.Debug::{to_repr}

///|
/// Text for people that names the rule or the algorithm.
pub fn TimestampError::message(self : TimestampError) -> String {
  match self {
    BadTimestamp(rule) => rule
    UnsupportedTimestamp(name) => "unsupported \{name}"
  }
}

///|
/// The ESS signing certificate reference of a signer (RFC 5035).
pub struct SigningCertificate {
  hash : @signature.HashAlgorithm
  cert_hash : Bytes
}

///|
/// The fields of an RFC 3161 TimeStampResp that verification uses.
pub struct Timestamp {
  /// The time of the timestamp: seconds since 1970 and nanoseconds.
  seconds : Int64
  nanos : Int
  imprint_hash : @signature.HashAlgorithm
  imprint : Bytes
  /// The DER bytes of the TSTInfo, which the message digest covers.
  tst_info : Bytes
  /// The issuer name (DER) and serial number content of the signer.
  signer_issuer : Bytes
  signer_serial : Bytes
  /// The certificates that the SignedData holds.
  certificates : Array[Bytes]
  digest_hash : @signature.HashAlgorithm
  message_digest : Bytes
  content_type : String
  signing_time : Int64?
  signing_certificate : SigningCertificate?
  /// The signed attributes as a DER SET, which the signature covers.
  signed_attributes : Bytes
  /// The hash that the signature algorithm names, when it names one.
  signature_hash : @signature.HashAlgorithm?
  signature : Bytes
}

///|
pub const SIGNED_DATA : String = "1.2.840.113549.1.7.2"

///|
pub const TST_INFO : String = "1.2.840.113549.1.9.16.1.4"

///|
fn bad(rule : String) -> TimestampError {
  BadTimestamp(rule)
}

///|
/// The hash of a digest AlgorithmIdentifier; its parameters are absent or NULL.
fn digest_algorithm(element : @der.Element) -> @signature.HashAlgorithm raise {
  let reader = element.children()
  let oid = reader.expect(@der.OID).oid()
  ignore(reader.optional(@der.NULL))
  reader.finish()
  match oid {
    "2.16.840.1.101.3.4.2.1" => Sha256
    "2.16.840.1.101.3.4.2.2" => Sha384
    "2.16.840.1.101.3.4.2.3" => Sha512
    "1.3.14.3.2.26" => raise UnsupportedTimestamp("hash SHA-1")
    other => raise UnsupportedTimestamp("hash \{other}")
  }
}

///|
/// The hash that a signature AlgorithmIdentifier names: `Some` for
/// ecdsa-with-SHA*, `None` for id-ecPublicKey (the digest algorithm applies).
fn signature_algorithm(element : @der.Element) -> @signature.HashAlgorithm? raise {
  let reader = element.children()
  let oid = reader.expect(@der.OID).oid()
  if reader.optional(@der.NULL) is Some(_) && oid.has_prefix("1.2.840.10045.") {
    raise bad("an ECDSA algorithm has parameters")
  }
  reader.finish()
  match oid {
    "1.2.840.10045.4.3.2" => Some(Sha256)
    "1.2.840.10045.4.3.3" => Some(Sha384)
    "1.2.840.10045.4.3.4" => Some(Sha512)
    "1.2.840.10045.2.1" => None
    "1.2.840.113549.1.1.1" | "1.2.840.113549.1.1.11" | "1.2.840.113549.1.1.12" | "1.2.840.113549.1.1.13" =>
      raise UnsupportedTimestamp("RSA signature")
    other => raise UnsupportedTimestamp("signature algorithm \{other}")
  }
}

///|
/// Read a DER TimeStampResp, as `signedTimestamp` holds it.
pub fn parse(bytes : BytesView) -> Timestamp raise TimestampError {
  parse_response(bytes) catch {
    @der.Malformed(rule) => raise bad("malformed DER: \{rule}")
    BadTimestamp(_) as err => raise err
    UnsupportedTimestamp(_) as err => raise err
    err => raise bad(err.to_string())
  }
}

///|
fn parse_response(bytes : BytesView) -> Timestamp raise {
  let response = @der.parse_tag(bytes, @der.SEQUENCE).children()
  let status = response.expect(@der.SEQUENCE).children()
  let code = status.expect(@der.INTEGER).small_int()
  guard code == 0 else { raise bad("the status is \{code}, not granted") }
  guard response.peek_tag() is Some(_) else { raise bad("the response has no token") }
  let content_info = response.expect(@der.SEQUENCE).children()
  response.finish()
  guard content_info.expect(@der.OID).oid() == SIGNED_DATA else {
    raise bad("the token is not SignedData")
  }
  let wrapper = content_info.expect(@der.context(0)).children()
  content_info.finish()
  let signed_data = wrapper.expect(@der.SEQUENCE).children()
  wrapper.finish()
  ignore(signed_data.expect(@der.INTEGER))
  ignore(signed_data.expect(@der.SET))
  let encapsulated = signed_data.expect(@der.SEQUENCE).children()
  guard encapsulated.expect(@der.OID).oid() == TST_INFO else {
    raise bad("the content is not a TSTInfo")
  }
  let content = encapsulated.expect(@der.context(0)).children()
  let tst_octets = content.expect(@der.OCTET_STRING).content
  content.finish()
  encapsulated.finish()
  let certificates = []
  if signed_data.optional(@der.context(0)) is Some(set) {
    let reader = set.children()
    while !reader.is_empty() {
      certificates.push(reader.expect(@der.SEQUENCE).raw.to_owned())
    }
  }
  ignore(signed_data.optional(@der.context(1)))
  let signer_infos = signed_data.expect(@der.SET).children()
  signed_data.finish()
  let signer = signer_infos.expect(@der.SEQUENCE).children()
  guard signer_infos.is_empty() else { raise bad("the token has more than one signer") }
  guard signer.expect(@der.INTEGER).small_int() == 1 else {
    raise bad("the signer is not named by issuer and serial number")
  }
  let sid = signer.expect(@der.SEQUENCE).children()
  let signer_issuer = sid.expect(@der.SEQUENCE).raw.to_owned()
  let signer_serial = sid.expect(@der.INTEGER).content.to_owned()
  sid.finish()
  let digest_hash = digest_algorithm(signer.expect(@der.SEQUENCE))
  guard signer.optional(@der.context(0)) is Some(attributes) else {
    raise bad("the signer has no signed attributes")
  }
  let signature_hash = signature_algorithm(signer.expect(@der.SEQUENCE))
  let signature = signer.expect(@der.OCTET_STRING).content.to_owned()
  ignore(signer.optional(@der.context(1)))
  signer.finish()
  // The signature covers the attributes as a DER SET OF (tag 0x31).
  let signed_attributes = Array::from_iter(attributes.raw.iter())
  signed_attributes[0] = b'\x31'
  let mut content_type = ""
  let mut message_digest : Bytes? = None
  let mut signing_time = None
  let mut signing_certificate = None
  let seen : Array[String] = []
  let list = attributes.children()
  while !list.is_empty() {
    let attribute = list.expect(@der.SEQUENCE).children()
    let oid = attribute.expect(@der.OID).oid()
    guard !seen.contains(oid) else { raise bad("the attribute \{oid} is repeated") }
    seen.push(oid)
    let values = attribute.expect(@der.SET).children()
    attribute.finish()
    let value = values.next()
    guard values.is_empty() else { raise bad("the attribute \{oid} has more than one value") }
    match oid {
      "1.2.840.113549.1.9.3" => content_type = value.oid()
      "1.2.840.113549.1.9.4" => {
        guard value.tag == @der.OCTET_STRING else { raise bad("bad message digest") }
        message_digest = Some(value.content.to_owned())
      }
      "1.2.840.113549.1.9.5" => signing_time = Some(value.time())
      "1.2.840.113549.1.9.16.2.47" => signing_certificate = Some(read_signing_certificate(value))
      _ => ()
    }
  }
  guard content_type == TST_INFO else {
    raise bad("the content type attribute is not id-ct-TSTInfo")
  }
  guard message_digest is Some(message_digest) else {
    raise bad("the signer has no message digest attribute")
  }
  let (seconds, nanos, imprint_hash, imprint) = read_tst_info(tst_octets)
  {
    seconds,
    nanos,
    imprint_hash,
    imprint,
    tst_info: tst_octets.to_owned(),
    signer_issuer,
    signer_serial,
    certificates,
    digest_hash,
    message_digest,
    content_type,
    signing_time,
    signing_certificate,
    signed_attributes: Bytes::from_array(signed_attributes),
    signature_hash,
    signature,
  }
}

///|
fn read_signing_certificate(value : @der.Element) -> SigningCertificate raise {
  let certificates = value.children().expect(@der.SEQUENCE).children()
  let first = certificates.expect(@der.SEQUENCE).children()
  let hash = match first.peek_tag() {
    Some(tag) if tag == @der.SEQUENCE => digest_algorithm(first.next())
    _ => Sha256
  }
  let cert_hash = first.expect(@der.OCTET_STRING).content.to_owned()
  { hash, cert_hash }
}

///|
fn read_tst_info(bytes : BytesView) -> (Int64, Int, @signature.HashAlgorithm, Bytes) raise {
  let info = @der.parse_tag(bytes, @der.SEQUENCE).children()
  guard info.expect(@der.INTEGER).small_int() == 1 else { raise bad("the TSTInfo version is not 1") }
  ignore(info.expect(@der.OID))
  let imprint_reader = info.expect(@der.SEQUENCE).children()
  let imprint_hash = digest_algorithm(imprint_reader.expect(@der.SEQUENCE))
  let imprint = imprint_reader.expect(@der.OCTET_STRING).content.to_owned()
  imprint_reader.finish()
  guard !imprint.is_empty() else { raise bad("the message imprint is empty") }
  ignore(info.expect(@der.INTEGER))
  let (seconds, nanos) = info.expect(@der.GENERALIZED_TIME).generalized_time()
  ignore(info.optional(@der.SEQUENCE))
  if info.optional(@der.BOOLEAN) is Some(ordering) {
    guard ordering.boolean() else { raise bad("ordering is encoded as false") }
  }
  ignore(info.optional(@der.INTEGER))
  ignore(info.optional(@der.context(0)))
  ignore(info.optional(@der.context(1)))
  info.finish()
  (seconds, nanos, imprint_hash, imprint)
}

///|
/// True when the message digest attribute is the hash of the TSTInfo and the
/// signature over the signed attributes verifies with `key`.
pub fn Timestamp::verify_signature(
  self : Timestamp,
  key : @signature.PublicKey,
) -> Bool {
  guard @signature.digest(self.digest_hash, self.tst_info) == self.message_digest else {
    return false
  }
  let hash = self.signature_hash.unwrap_or(self.digest_hash)
  key.verify(self.signed_attributes, self.signature, hash~)
}
