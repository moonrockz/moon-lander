///|
/// A certificate that cannot be read.
pub suberror X509Error {
  /// The certificate breaks the rule that the text names.
  BadCertificate(String)
} derive(Debug)

///|
pub extend X509Error with @debug.Debug::{to_repr}

///|
pub fn X509Error::message(self : X509Error) -> String {
  let BadCertificate(rule) = self
  "bad certificate: \{rule}"
}

///|
/// One certificate extension.
pub struct Extension {
  oid : String
  critical : Bool
  /// The content of the extnValue OCTET STRING.
  value : Bytes
}

///|
/// The basic constraints of a certificate.
pub struct BasicConstraints {
  is_ca : Bool
  path_length : Int?
}

///|
/// The fields of an X.509 v3 certificate that Sigstore verification reads.
pub struct Certificate {
  /// All of the DER bytes.
  raw : Bytes
  /// The content bytes of the serial number INTEGER.
  serial : Bytes
  /// The DER bytes of the TBSCertificate, which the issuer signs.
  tbs : Bytes
  signature_algorithm : String
  signature : Bytes
  /// The DER bytes of the issuer and subject names.
  issuer : Bytes
  subject : Bytes
  /// The validity bounds in seconds since 1970, both inclusive.
  not_before : Int64
  not_after : Int64
  /// The DER SubjectPublicKeyInfo.
  spki : Bytes
  extensions : Array[Extension]
  basic_constraints : BasicConstraints?
  /// The key usage bits, bit 0 first, when the extension is present.
  key_usage : Int?
  /// The extended key usage OIDs, when the extension is present.
  extended_key_usage : Array[String]?
  /// The URI subject alternative names.
  san_uris : Array[String]
  /// The email subject alternative names.
  san_emails : Array[String]
  authority_key_id : Bytes?
  subject_key_id : Bytes?
}

///|
pub const KEY_USAGE_DIGITAL_SIGNATURE : Int = 1

///|
pub const KEY_USAGE_CERT_SIGN : Int = 32

///|
pub const EKU_CODE_SIGNING : String = "1.3.6.1.5.5.7.3.3"

///|
pub const EKU_ANY : String = "2.5.29.37.0"

///|
pub const SCT_LIST_OID : String = "1.3.6.1.4.1.11129.2.4.2"

///|
/// Extensions that this reader understands. A critical extension that is not
/// in this list makes a certificate unusable.
let handled_extensions : Array[String] = [
  "2.5.29.14", "2.5.29.15", "2.5.29.17", "2.5.29.19", "2.5.29.35", "2.5.29.37", "2.5.29.32",
]

///|
fn bad(err : @der.DerError) -> X509Error {
  BadCertificate(err.message())
}

///|
/// Read a DER certificate.
pub fn parse(raw : BytesView) -> Certificate raise X509Error {
  parse_der(raw) catch {
    @der.Malformed(_) as err => raise bad(err)
    BadCertificate(_) as err => raise err
    err => raise BadCertificate(err.to_string())
  }
}

///|
fn parse_der(raw : BytesView) -> Certificate raise {
  let outer = @der.parse_tag(raw, @der.SEQUENCE).children()
  let tbs = outer.expect(@der.SEQUENCE)
  let outer_algorithm = outer.expect(@der.SEQUENCE)
  let algorithm = read_algorithm(outer_algorithm)
  let signature = outer.expect(@der.BIT_STRING).bit_string_bytes()
  outer.finish()
  let fields = tbs.children()
  let version = match fields.optional(@der.context(0)) {
    Some(element) => {
      let inner = element.children()
      let value = inner.expect(@der.INTEGER).small_int()
      inner.finish()
      value
    }
    None => 0
  }
  guard version == 2 else { raise BadCertificate("not an X.509 v3 certificate") }
  let serial = fields.expect(@der.INTEGER).content.to_owned()
  // RFC 5280, section 4.1.1.2: the same AlgorithmIdentifier, parameters too.
  let inner_algorithm = fields.expect(@der.SEQUENCE)
  ignore(read_algorithm(inner_algorithm))
  guard inner_algorithm.raw == outer_algorithm.raw else {
    raise BadCertificate("the two signature algorithms differ")
  }
  let issuer = fields.expect(@der.SEQUENCE)
  let validity = fields.expect(@der.SEQUENCE).children()
  let not_before = validity.next().time()
  let not_after = validity.next().time()
  validity.finish()
  let subject = fields.expect(@der.SEQUENCE)
  let spki = fields.expect(@der.SEQUENCE)
  ignore(fields.optional(@der.context_primitive(1)))
  ignore(fields.optional(@der.context_primitive(2)))
  let extensions = match fields.optional(@der.context(3)) {
    Some(element) => read_extensions(element)
    None => []
  }
  fields.finish()
  let certificate = {
    raw: raw.to_owned(),
    serial,
    tbs: tbs.raw.to_owned(),
    signature_algorithm: algorithm,
    signature: signature.to_owned(),
    issuer: issuer.raw.to_owned(),
    subject: subject.raw.to_owned(),
    not_before,
    not_after,
    spki: spki.raw.to_owned(),
    extensions,
    basic_constraints: None,
    key_usage: None,
    extended_key_usage: None,
    san_uris: [],
    san_emails: [],
    authority_key_id: None,
    subject_key_id: None,
  }
  decode_extensions(certificate)
}

///|
fn read_algorithm(element : @der.Element) -> String raise @der.DerError {
  let reader = element.children()
  let oid = reader.expect(@der.OID).oid()
  // ECDSA algorithms have no parameters (RFC 5758); RSA algorithms have NULL.
  if reader.optional(@der.NULL) is Some(_) && oid.has_prefix("1.2.840.10045.4.") {
    raise @der.Malformed("an ECDSA algorithm has parameters")
  }
  reader.finish()
  oid
}

///|
fn read_extensions(element : @der.Element) -> Array[Extension] raise {
  let wrapper = element.children()
  let list = wrapper.expect(@der.SEQUENCE).children()
  wrapper.finish()
  let extensions : Array[Extension] = []
  while !list.is_empty() {
    let extension = list.expect(@der.SEQUENCE).children()
    let oid = extension.expect(@der.OID).oid()
    let critical = match extension.optional(@der.BOOLEAN) {
      Some(flag) => {
        let value = flag.boolean()
        // DER omits a default value.
        guard value else { raise BadCertificate("critical is encoded as false") }
        value
      }
      None => false
    }
    let value = extension.expect(@der.OCTET_STRING).content.to_owned()
    extension.finish()
    guard !extensions.iter().any(e => e.oid == oid) else {
      raise BadCertificate("the extension \{oid} is repeated")
    }
    extensions.push({ oid, critical, value })
  }
  extensions
}

///|
fn decode_extensions(certificate : Certificate) -> Certificate raise {
  let mut result = certificate
  for extension in certificate.extensions {
    let value = extension.value[:]
    match extension.oid {
      "2.5.29.19" => {
        let reader = @der.parse_tag(value, @der.SEQUENCE).children()
        let is_ca = match reader.optional(@der.BOOLEAN) {
          Some(flag) => {
            // DER omits the default value false.
            guard flag.boolean() else {
              raise BadCertificate("cA is encoded as false")
            }
            true
          }
          None => false
        }
        let path_length = match reader.optional(@der.INTEGER) {
          Some(number) => Some(number.small_int())
          None => None
        }
        reader.finish()
        result = { ..result, basic_constraints: Some({ is_ca, path_length }) }
      }
      "2.5.29.15" =>
        result = {
          ..result,
          key_usage: Some(@der.parse_tag(value, @der.BIT_STRING).named_bits()),
        }
      "2.5.29.37" => {
        let reader = @der.parse_tag(value, @der.SEQUENCE).children()
        let usages = []
        while !reader.is_empty() {
          usages.push(reader.expect(@der.OID).oid())
        }
        result = { ..result, extended_key_usage: Some(usages) }
      }
      "2.5.29.17" => {
        let reader = @der.parse_tag(value, @der.SEQUENCE).children()
        let uris = []
        let emails = []
        while !reader.is_empty() {
          let name = reader.next()
          if name.tag == @der.context_primitive(6) {
            uris.push(ascii(name.content))
          } else if name.tag == @der.context_primitive(1) {
            emails.push(ascii(name.content))
          }
        }
        result = { ..result, san_uris: uris, san_emails: emails }
      }
      "2.5.29.35" => {
        let reader = @der.parse_tag(value, @der.SEQUENCE).children()
        match reader.optional(@der.context_primitive(0)) {
          Some(id) => result = { ..result, authority_key_id: Some(id.content.to_owned()) }
          None => ()
        }
      }
      "2.5.29.14" =>
        result = {
          ..result,
          subject_key_id: Some(
            @der.parse_tag(value, @der.OCTET_STRING).content.to_owned(),
          ),
        }
      _ => ()
    }
  }
  result
}

///|
fn ascii(bytes : BytesView) -> String raise X509Error {
  for byte in bytes {
    guard byte >= b' ' && byte <= b'~' else {
      raise BadCertificate("a name is not printable ASCII")
    }
  }
  @utf8.decode(bytes) catch {
    _ => raise BadCertificate("a name is not ASCII")
  }
}

///|
/// The extension with `oid`, if present.
pub fn Certificate::extension(self : Certificate, oid : String) -> Extension? {
  self.extensions.iter().find_first(e => e.oid == oid)
}

///|
/// The OID of the first critical extension that this reader does not
/// understand, ignoring the OIDs in `allowed`.
pub fn Certificate::unhandled_critical(
  self : Certificate,
  allowed? : Array[String] = [],
) -> String? {
  for extension in self.extensions {
    if extension.critical &&
      !handled_extensions.contains(extension.oid) &&
      !allowed.contains(extension.oid) {
      return Some(extension.oid)
    }
  }
  None
}

///|
/// True when `time` (seconds since 1970) is inside the validity bounds.
pub fn Certificate::valid_at(self : Certificate, time : Int64) -> Bool {
  self.not_before <= time && time <= self.not_after
}

///|
/// The hash of a signature algorithm OID that the verifier supports.
pub fn signature_hash(algorithm : String) -> @signature.HashAlgorithm? {
  match algorithm {
    "1.2.840.10045.4.3.2" => Some(Sha256)
    "1.2.840.10045.4.3.3" => Some(Sha384)
    "1.2.840.10045.4.3.4" => Some(Sha512)
    _ => None
  }
}

///|
/// True when `issuer` names this certificate's issuer and its key signed it.
pub fn Certificate::is_issued_by(self : Certificate, issuer : Certificate) -> Bool {
  guard self.issuer == issuer.subject else { return false }
  guard signature_hash(self.signature_algorithm) is Some(hash) else { return false }
  let key = @signature.PublicKey::from_spki(issuer.spki) catch {
    _ => return false
  }
  key.verify(self.tbs, self.signature, hash~)
}

///|
/// Decode a Fulcio extension value: the raw text of `.1.1` to `.1.6`, and a
/// DER UTF8String for `.1.8` and later.
pub fn fulcio_value(extension : Extension) -> String raise X509Error {
  let prefix = "1.3.6.1.4.1.57264.1."
  guard extension.oid.has_prefix(prefix) else {
    raise BadCertificate("not a Fulcio extension")
  }
  let arc = @string.parse_int(extension.oid[prefix.length():]) catch {
    _ => raise BadCertificate("bad Fulcio extension OID")
  }
  if arc <= 6 {
    @utf8.decode(extension.value) catch {
      _ => raise BadCertificate("the Fulcio extension \{extension.oid} is not UTF-8")
    }
  } else {
    let element = @der.parse_tag(extension.value, @der.UTF8_STRING) catch {
      err => raise bad(err)
    }
    element.text() catch {
      err => raise bad(err)
    }
  }
}

///|
/// The DER certificates of a PEM text, in order.
pub fn decode_pem(text : String) -> Array[Bytes] raise X509Error {
  let certificates = []
  let begin = "-----BEGIN CERTIFICATE-----"
  let end = "-----END CERTIFICATE-----"
  let mut rest = text[:]
  while rest.find(begin) is Some(start) {
    let after = rest[start + begin.length():]
    guard after.find(end) is Some(stop) else {
      raise BadCertificate("PEM block without an end line")
    }
    let body = after[:stop]
    let der = @encoding.decode_base64(
      body.to_owned().replace_all(old="\n", new="").replace_all(old="\r", new=""),
    ) catch {
      _ => raise BadCertificate("PEM block is not base64")
    }
    certificates.push(der)
    rest = after[stop + end.length():]
  }
  guard !certificates.is_empty() else { raise BadCertificate("no PEM certificate") }
  certificates
}

///|
/// The TBSCertificate without the extension `oid`, as a CT precertificate
/// signs it (RFC 6962, section 3.2).
pub fn Certificate::tbs_without(self : Certificate, oid : String) -> Bytes raise X509Error {
  rebuild(self.tbs, oid) catch {
    @der.Malformed(_) as err => raise bad(err)
  }
}

///|
fn rebuild(tbs : Bytes, oid : String) -> Bytes raise @der.DerError {
  let fields = @der.parse_tag(tbs, @der.SEQUENCE).children()
  let out : Array[Byte] = []
  while !fields.is_empty() {
    let field = fields.next()
    if field.tag == @der.context(3) {
      let wrapper = field.children()
      let list = wrapper.expect(@der.SEQUENCE).children()
      let kept : Array[Byte] = []
      while !list.is_empty() {
        let extension = list.expect(@der.SEQUENCE)
        let reader = extension.children()
        if reader.expect(@der.OID).oid() != oid {
          for byte in extension.raw {
            kept.push(byte)
          }
        }
      }
      let sequence = @der.encode(@der.SEQUENCE, Bytes::from_array(kept))
      for byte in @der.encode(@der.context(3), sequence) {
        out.push(byte)
      }
    } else {
      for byte in field.raw {
        out.push(byte)
      }
    }
  }
  @der.encode(@der.SEQUENCE, Bytes::from_array(out))
}
