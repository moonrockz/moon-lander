///|
fn hex(text : String) -> Bytes raise {
  @encoding.decode_hex(text)
}

///|
fn base64(text : String) -> Bytes raise {
  @encoding.decode_base64(text)
}

///|
fn concat(parts : Array[Bytes]) -> Bytes {
  let out : Array[Byte] = []
  for part in parts {
    for byte in part {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
/// The text of a fixture file in a generated fixture group.
fn fixture(group : Array[(String, String)], path : String) -> String {
  for file in group {
    if file.0 == path {
      return file.1
    }
  }
  abort("no fixture \{path}")
}

///|
/// The DER leaf certificate of a GitHub attestation bundle.
fn github_leaf(bundle : String) -> Bytes raise {
  guard @json.parse(fixture(@fixtures.github, bundle)) is Object(root) &&
    root.get("verificationMaterial") is Some(Object(material)) &&
    material.get("certificate") is Some(Object(certificate)) &&
    certificate.get("rawBytes") is Some(String(raw)) else {
    fail("no leaf certificate in \{bundle}")
  }
  base64(raw)
}

///|
let morphir_bundle : String = "morphir-rust-provider-snapshot-0.2.0.sigstore.json"

///|
let github_bundles : Array[String] = [
  "morphir-rust-provider-snapshot-0.2.0.sigstore.json", "cli-2.50.0.sigstore.json",
  "cli-2.83.0.sigstore.json",
]

///|
/// The public-good `sigstore-intermediate` (certificateAuthorities[1]).
let intermediate_base64 : String = "MIICGjCCAaGgAwIBAgIUALnViVfnU0brJasmRkHrn/UnfaQwCgYIKoZIzj0EAwMwKjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MREwDwYDVQQDEwhzaWdzdG9yZTAeFw0yMjA0MTMyMDA2MTVaFw0zMTEwMDUxMzU2NThaMDcxFTATBgNVBAoTDHNpZ3N0b3JlLmRldjEeMBwGA1UEAxMVc2lnc3RvcmUtaW50ZXJtZWRpYXRlMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE8RVS/ysH+NOvuDZyPIZtilgUF9NlarYpAd9HP1vBBH1U5CV77LSS7s0ZiH4nE7Hv7ptS6LvvR/STk798LVgMzLlJ4HeIfF3tHSaexLcYpSASr1kS0N/RgBJz/9jWCiXno3sweTAOBgNVHQ8BAf8EBAMCAQYwEwYDVR0lBAwwCgYIKwYBBQUHAwMwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU39Ppz1YkEZb5qNjpKFWixi4YZD8wHwYDVR0jBBgwFoAUWMAeX5FFpWapesyQoZMi0CrFxfowCgYIKoZIzj0EAwMDZwAwZAIwPCsQK4DYiZYDPIaDi5HFKnfxXx6ASSVmERfsynYBiX2X6SJRnZU84/9DZdnFvvxmAjBOt6QpBlc4J/0DxvkTCqpclvziL6BCCPnjdlIB3Pu3BxsPmygUY7Ii2zbdCdliiow="

///|
/// The public-good root `sigstore` (certificateAuthorities[1]).
let root_base64 : String = "MIIB9zCCAXygAwIBAgIUALZNAPFdxHPwjeDloDwyYChAO/4wCgYIKoZIzj0EAwMwKjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MREwDwYDVQQDEwhzaWdzdG9yZTAeFw0yMTEwMDcxMzU2NTlaFw0zMTEwMDUxMzU2NThaMCoxFTATBgNVBAoTDHNpZ3N0b3JlLmRldjERMA8GA1UEAxMIc2lnc3RvcmUwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAT7XeFT4rb3PQGwS4IajtLk3/OlnpgangaBclYpsYBr5i+4ynB07ceb3LP0OIOZdxexX69c5iVuyJRQ+Hz05yi+UF3uBWAlHpiS5sh0+H2GHE7SXrk1EC5m1Tr19L9gg92jYzBhMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBRYwB5fkUWlZql6zJChkyLQKsXF+jAfBgNVHSMEGDAWgBRYwB5fkUWlZql6zJChkyLQKsXF+jAKBggqhkjOPQQDAwNpADBmAjEAj1nHeXZp+13NWBNa+EDsDP8G1WWg1tCMWP/WHPqpaVo0jhsweNFZgSs0eE7wYI4qAjEA2WB9ot98sIkoF3vZYdd3/VtWB5b9TNMea7Ix/stJ5TfcLLeABLE4BNJOsQ4vnBHJ"

///|
/// The first public-good root (certificateAuthorities[0]): the same subject
/// name as `root_base64`, with another key.
let old_root_base64 : String = "MIIB+DCCAX6gAwIBAgITNVkDZoCiofPDsy7dfm6geLbuhzAKBggqhkjOPQQDAzAqMRUwEwYDVQQKEwxzaWdzdG9yZS5kZXYxETAPBgNVBAMTCHNpZ3N0b3JlMB4XDTIxMDMwNzAzMjAyOVoXDTMxMDIyMzAzMjAyOVowKjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MREwDwYDVQQDEwhzaWdzdG9yZTB2MBAGByqGSM49AgEGBSuBBAAiA2IABLSyA7Ii5k+pNO8ZEWY0ylemWDowOkNa3kL+GZE5Z5GWehL9/A9bRNA3RbrsZ5i0JcastaRL7Sp5fp/jD5dxqc/UdTVnlvS16an+2Yfswe/QuLolRUCrcOE2+2iA5+tzd6NmMGQwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQIMAYBAf8CAQEwHQYDVR0OBBYEFMjFHQBBmiQpMlEk6w2uSu1KBtPsMB8GA1UdIwQYMBaAFMjFHQBBmiQpMlEk6w2uSu1KBtPsMAoGCCqGSM49BAMDA2gAMGUCMH8liWJfMui6vXXBhjDgY4MwslmN/TJxVe/83WrFomwmNf056y1X48F9c4m3a3ozXAIxAKjRay5/aj/jsKKGIkmQatjI8uupHr/+CxFvaJWmpYqNkLDGRU+9orzh5hI2RrcuaQ=="

///|
/// The rule of a `BadCertificate`, or "ok".
fn parse_outcome(raw : BytesView) -> String {
  try {
    ignore(@x509.parse(raw))
    "ok"
  } catch {
    BadCertificate(rule) => rule
  }
}

///|
/// The raw DER elements inside a constructed element.
fn children_raw(der : BytesView) -> Array[Bytes] raise {
  let reader = @der.parse(der).children()
  let out = []
  while !reader.is_empty() {
    out.push(reader.next().raw.to_owned())
  }
  out
}

///|
fn sequence(parts : Array[Bytes]) -> Bytes {
  @der.encode(@der.SEQUENCE, concat(parts))
}

///|
/// A certificate split into its TBS fields, outer algorithm and signature.
struct Parts {
  fields : Array[Bytes]
  algorithm : Bytes
  signature : Bytes
}

///|
fn split(raw : BytesView) -> Parts raise {
  let outer = children_raw(raw)
  assert_eq(outer.length(), 3)
  { fields: children_raw(outer[0]), algorithm: outer[1], signature: outer[2] }
}

///|
fn Parts::join(self : Parts) -> Bytes {
  sequence([sequence(self.fields), self.algorithm, self.signature])
}

///|
/// The extensions of the TBS fields, as raw DER.
fn Parts::extensions(self : Parts) -> Array[Bytes] raise {
  let wrapper = self.fields[self.fields.length() - 1]
  let inner = children_raw(wrapper)
  assert_eq(inner.length(), 1)
  children_raw(inner[0])
}

///|
/// The parts with other extensions.
fn Parts::with_extensions(self : Parts, extensions : Array[Bytes]) -> Parts {
  let fields = self.fields.copy()
  fields[fields.length() - 1] = @der.encode(@der.context(3), sequence(extensions))
  { ..self, fields, }
}

///|
/// An extension with `oid` (DER content hex), an optional critical flag (DER
/// content hex) and `value`.
fn extension(oid : String, critical : String?, value : Bytes) -> Bytes raise {
  let parts = [@der.encode(@der.OID, hex(oid))]
  if critical is Some(flag) {
    parts.push(@der.encode(@der.BOOLEAN, hex(flag)))
  }
  parts.push(@der.encode(@der.OCTET_STRING, value))
  sequence(parts)
}

///|
test "the certificate builder gives back the real certificate" {
  let leaf = github_leaf(morphir_bundle)
  assert_eq(split(leaf).join(), leaf)
  let parts = split(leaf)
  assert_eq(parts.with_extensions(parts.extensions()).join(), leaf)
}

///|
test "the fields of a real Fulcio leaf certificate" {
  let leaf = @x509.parse(github_leaf(morphir_bundle))
  let intermediate = @x509.parse(base64(intermediate_base64))
  assert_eq(leaf.signature_algorithm, "1.2.840.10045.4.3.3")
  assert_eq(@x509.signature_hash(leaf.signature_algorithm), Some(Sha384))
  assert_eq(leaf.issuer, intermediate.subject)
  assert_eq(leaf.not_before, 1792133281L)
  assert_eq(leaf.not_after - leaf.not_before, 600L)
  assert_true(leaf.valid_at(leaf.not_before))
  assert_true(leaf.valid_at(leaf.not_after))
  assert_false(leaf.valid_at(leaf.not_before - 1L))
  assert_false(leaf.valid_at(leaf.not_after + 1L))
  assert_eq(leaf.key_usage, Some(@x509.KEY_USAGE_DIGITAL_SIGNATURE))
  assert_eq(leaf.extended_key_usage, Some([@x509.EKU_CODE_SIGNING]))
  assert_true(leaf.basic_constraints is None)
  assert_eq(leaf.san_uris, [
    "https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/tags/provider-snapshot/v0.2.0",
  ])
  assert_eq(leaf.san_emails, [])
  assert_eq(
    leaf.authority_key_id.map(id => @encoding.encode_hex(id)),
    Some("dfd3e9cf56241196f9a8d8e92855a2c62e18643f"),
  )
  assert_eq(leaf.authority_key_id, intermediate.subject_key_id)
  assert_true(leaf.subject_key_id is None)
  assert_true(leaf.extension(@x509.SCT_LIST_OID) is Some(_))
  assert_true(leaf.extension("1.2.3.4") is None)
  assert_eq(leaf.unhandled_critical(), None)
  // The leaf key is a P-256 key.
  let key = @signature.PublicKey::from_spki(leaf.spki)
  assert_true(key.kind is EcdsaP256)
  // The parse keeps the TBS bytes that the issuer signed.
  assert_eq(split(leaf.raw).fields.length(), 8)
}

///|
fn fulcio(certificate : @x509.Certificate, arc : Int) -> String raise {
  guard certificate.extension("1.3.6.1.4.1.57264.1.\{arc}") is Some(extension) else {
    fail("no Fulcio extension .1.\{arc}")
  }
  @x509.fulcio_value(extension)
}

///|
test "Fulcio extension values" {
  let leaf = @x509.parse(github_leaf(morphir_bundle))
  // .1.1 to .1.6 are raw text.
  assert_eq(fulcio(leaf, 1), "https://token.actions.githubusercontent.com")
  assert_eq(fulcio(leaf, 2), "push")
  assert_eq(fulcio(leaf, 3), "6a481ec17cf75d889ad363b008ece2ba0ea6e05f")
  assert_eq(fulcio(leaf, 5), "finos/morphir-rust")
  assert_eq(fulcio(leaf, 6), "refs/tags/provider-snapshot/v0.2.0")
  // .1.8 and later are DER UTF8String values.
  assert_eq(fulcio(leaf, 8), "https://token.actions.githubusercontent.com")
  assert_eq(
    fulcio(leaf, 9),
    "https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/tags/provider-snapshot/v0.2.0",
  )
  assert_eq(fulcio(leaf, 11), "github-hosted")
  assert_eq(fulcio(leaf, 12), "https://github.com/finos/morphir-rust")
  assert_eq(fulcio(leaf, 14), "refs/tags/provider-snapshot/v0.2.0")
  assert_eq(fulcio(leaf, 15), "513894754")
  assert_eq(fulcio(leaf, 17), "35377814")
  assert_eq(fulcio(leaf, 22), "public")
  assert_eq(
    fulcio(leaf, 24),
    "repo:finos/morphir-rust:ref:refs/tags/provider-snapshot/v0.2.0",
  )
  // Another extension is not a Fulcio value.
  guard leaf.extension("2.5.29.15") is Some(key_usage) else { fail("no KU") }
  let refused = try {
    ignore(@x509.fulcio_value(key_usage))
    "ok"
  } catch {
    BadCertificate(rule) => rule
  }
  assert_eq(refused, "not a Fulcio extension")
}

///|
/// The Fulcio OID prefix `1.3.6.1.4.1.57264.1` as DER content hex.
let fulcio_oid : String = "2b0601040183bf3001"

///|
test "Fulcio values with the wrong encoding are refused" {
  let parts = split(github_leaf(morphir_bundle))
  let extensions = parts.extensions()
  // The leaf has no .1.7, .1.23 or .1.25: raw text where DER is due, a
  // PrintableString, and a UTF8String that is not UTF-8.
  extensions.push(extension(fulcio_oid + "07", None, b"https://example.com"))
  extensions.push(extension(fulcio_oid + "17", None, b"\x13\x02ab"))
  extensions.push(extension(fulcio_oid + "19", None, b"\x0c\x01\xff"))
  extensions.push(extension(fulcio_oid + "8100", None, b"\x0c\x02ab"))
  let leaf = @x509.parse(parts.with_extensions(extensions).join())
  for arc in [7, 23, 25] {
    let refused = try {
      ignore(fulcio(leaf, arc))
      false
    } catch {
      @x509.BadCertificate(_) => true
      _ => false
    }
    assert_true(refused, msg=".1.\{arc}")
  }
  // .1.128 is a DER UTF8String.
  assert_eq(fulcio(leaf, 128), "ab")
}

///|
test "the fields of the public-good CA certificates" {
  let intermediate = @x509.parse(base64(intermediate_base64))
  let root = @x509.parse(base64(root_base64))
  assert_eq(
    intermediate.key_usage,
    Some(@x509.KEY_USAGE_CERT_SIGN | (1 << 6)),
  )
  assert_true(
    intermediate.basic_constraints is Some(constraints) &&
    constraints.is_ca &&
    constraints.path_length == Some(0),
  )
  assert_true(
    root.basic_constraints is Some(constraints) &&
    constraints.is_ca &&
    constraints.path_length is None,
  )
  assert_eq(intermediate.authority_key_id, root.subject_key_id)
  assert_eq(root.authority_key_id, root.subject_key_id)
  assert_eq(intermediate.extended_key_usage, Some([@x509.EKU_CODE_SIGNING]))
  assert_eq(root.unhandled_critical(), None)
  assert_eq(intermediate.unhandled_critical(), None)
}

///|
test "is_issued_by follows the chain in one direction" {
  let intermediate = @x509.parse(base64(intermediate_base64))
  let root = @x509.parse(base64(root_base64))
  let old_root = @x509.parse(base64(old_root_base64))
  assert_eq(old_root.subject, root.subject)
  for bundle in github_bundles {
    let leaf = @x509.parse(github_leaf(bundle))
    assert_true(leaf.is_issued_by(intermediate), msg=bundle)
    assert_false(leaf.is_issued_by(root), msg=bundle)
    assert_false(leaf.is_issued_by(leaf), msg=bundle)
    assert_false(intermediate.is_issued_by(leaf), msg=bundle)
  }
  assert_true(intermediate.is_issued_by(root))
  assert_true(root.is_issued_by(root))
  assert_true(old_root.is_issued_by(old_root))
  assert_false(root.is_issued_by(intermediate))
  // The same name with another key.
  assert_false(intermediate.is_issued_by(old_root))
  assert_false(root.is_issued_by(old_root))
}

///|
test "is_issued_by refuses a changed signature or an unknown algorithm" {
  let intermediate = @x509.parse(base64(intermediate_base64))
  let parts = split(github_leaf(morphir_bundle))
  // The last byte of s changes; the signature stays strict DER.
  let signature = parts.signature.to_array()
  let last = signature.length() - 1
  signature[last] = signature[last] ^ b'\x01'
  let changed = @x509.parse(
    { ..parts, signature: Bytes::from_array(signature) }.join(),
  )
  assert_false(changed.is_issued_by(intermediate))
  // A changed TBS field (the serial number) breaks the signature.
  let fields = parts.fields.copy()
  let serial = fields[1].to_array()
  serial[serial.length() - 1] = serial[serial.length() - 1] ^ b'\x01'
  fields[1] = Bytes::from_array(serial)
  assert_false(@x509.parse({ ..parts, fields, }.join()).is_issued_by(intermediate))
  // RSA with SHA-256 on both sides is a signature algorithm that the
  // verifier does not know.
  let rsa = hex("300d06092a864886f70d01010b0500")
  let rsa_fields = parts.fields.copy()
  rsa_fields[2] = rsa
  let unknown = @x509.parse({ fields: rsa_fields, algorithm: rsa, signature: parts.signature }.join())
  assert_eq(unknown.signature_algorithm, "1.2.840.113549.1.1.11")
  assert_eq(@x509.signature_hash(unknown.signature_algorithm), None)
  assert_false(unknown.is_issued_by(intermediate))
}

///|
test "signature_hash knows the ECDSA SHA-2 algorithms" {
  assert_eq(@x509.signature_hash("1.2.840.10045.4.3.2"), Some(Sha256))
  assert_eq(@x509.signature_hash("1.2.840.10045.4.3.3"), Some(Sha384))
  assert_eq(@x509.signature_hash("1.2.840.10045.4.3.4"), Some(Sha512))
  assert_eq(@x509.signature_hash("1.2.840.10045.4.3.1"), None)
  assert_eq(@x509.signature_hash("1.2.840.113549.1.1.11"), None)
}

///|
/// The OID of a raw DER extension.
fn oid_of(raw : Bytes) -> String raise {
  @der.parse(raw).children().expect(@der.OID).oid()
}

///|
/// The OIDs of the extensions of a DER TBSCertificate.
fn extension_oids(tbs : Bytes) -> Array[String] raise {
  let fields = children_raw(tbs)
  let wrapper = fields[fields.length() - 1]
  assert_eq(@der.parse(wrapper).tag, @der.context(3))
  children_raw(children_raw(wrapper)[0]).map(oid_of)
}

///|
test "tbs_without removes exactly the SCT extension" {
  for bundle in github_bundles {
    let leaf = @x509.parse(github_leaf(bundle))
    let without = leaf.tbs_without(@x509.SCT_LIST_OID)
    let expected = leaf.extensions
      .filter(e => e.oid != @x509.SCT_LIST_OID)
      .map(e => e.oid)
    assert_eq(expected.length(), leaf.extensions.length() - 1, msg=bundle)
    assert_eq(extension_oids(without), expected, msg=bundle)
    assert_eq(
      extension_oids(leaf.tbs),
      leaf.extensions.map(e => e.oid),
      msg=bundle,
    )
    // The other fields are the same bytes.
    let before = children_raw(leaf.tbs)
    let after = children_raw(without)
    assert_eq(after.length(), before.length(), msg=bundle)
    for i in 0..<(before.length() - 1) {
      assert_eq(after[i], before[i], msg=bundle)
    }
    // The kept extensions are the same bytes.
    let kept_before = children_raw(children_raw(before[before.length() - 1])[0])
    let kept_after = children_raw(children_raw(after[after.length() - 1])[0])
    let mut j = 0
    for raw in kept_before {
      if oid_of(raw) != @x509.SCT_LIST_OID {
        assert_eq(kept_after[j], raw, msg=bundle)
        j += 1
      }
    }
    assert_eq(j, kept_after.length())
    // Without an extension that is not there, the TBS is the same.
    assert_eq(leaf.tbs_without("1.2.3.4"), leaf.tbs, msg=bundle)
  }
}

///|
/// A PEM block of `der`, with lines of 64 characters and `newline`.
fn pem(der : Bytes, newline : String) -> String {
  let text = @encoding.encode_base64(der)
  let out = StringBuilder()
  out.write_string("-----BEGIN CERTIFICATE-----\{newline}")
  let mut at = 0
  while at < text.length() {
    let end = if at + 64 < text.length() { at + 64 } else { text.length() }
    out.write_string(text[at:end].to_owned())
    out.write_string(newline)
    at = end
  }
  out.write_string("-----END CERTIFICATE-----\{newline}")
  out.to_string()
}

///|
/// The rule of a `BadCertificate` from `decode_pem`, or the count.
fn pem_outcome(text : String) -> String {
  try {
    "ok \{@x509.decode_pem(text).length()}"
  } catch {
    BadCertificate(rule) => rule
  }
}

///|
test "decode_pem reads one or more certificates in order" {
  let intermediate = base64(intermediate_base64)
  let root = base64(root_base64)
  assert_eq(@x509.decode_pem(pem(intermediate, "\n")), [intermediate])
  assert_eq(@x509.decode_pem(pem(root, "\r\n")), [root])
  assert_eq(
    @x509.decode_pem(
      "text before\n" + pem(intermediate, "\n") + "between\n" + pem(root, "\n"),
    ),
    [intermediate, root],
  )
  // The last block has no final newline.
  let last = pem(root, "\n")
  assert_eq(@x509.decode_pem(last[:last.length() - 1].to_owned()), [root])
}

///|
test "decode_pem rules" {
  let intermediate = base64(intermediate_base64)
  let block = pem(intermediate, "\n")
  assert_eq(pem_outcome(""), "no PEM certificate")
  assert_eq(pem_outcome("hello\n"), "no PEM certificate")
  assert_eq(
    pem_outcome(block.replace(old="-----END CERTIFICATE-----", new="")),
    "PEM block without an end line",
  )
  assert_eq(
    pem_outcome(block + block.replace(old="-----END CERTIFICATE-----", new="")),
    "PEM block without an end line",
  )
  assert_eq(
    pem_outcome(block.replace(old="MIIC", new="M!IC")),
    "PEM block is not base64",
  )
  // A missing character breaks the base64 length.
  assert_eq(
    pem_outcome(block.replace(old="MIIC", new="MIC")),
    "PEM block is not base64",
  )
}

///|
test "malformed certificates are refused" {
  let leaf = github_leaf(morphir_bundle)
  let parts = split(leaf)
  assert_eq(parse_outcome(leaf), "ok")
  // Truncated, a trailing byte and empty input.
  assert_true(parse_outcome(leaf[:leaf.length() - 1]).has_prefix("malformed DER"))
  assert_true(parse_outcome(concat([leaf, b"\x00"])).has_prefix("malformed DER"))
  assert_true(parse_outcome(b"").has_prefix("malformed DER"))
  // No signature after the algorithm.
  assert_true(
    parse_outcome(sequence([sequence(parts.fields), parts.algorithm])).has_prefix(
      "malformed DER",
    ),
  )
  // A v1 certificate has no version field; v2 is version 1.
  assert_eq(
    parse_outcome({ ..parts, fields: parts.fields[1:].to_owned() }.join()),
    "not an X.509 v3 certificate",
  )
  let v2 = parts.fields.copy()
  v2[0] = hex("a003020101")
  assert_eq(parse_outcome({ ..parts, fields: v2 }.join()), "not an X.509 v3 certificate")
  // The two signature algorithms differ: another hash, or the same OID with
  // NULL parameters on one side.
  let sha256 = hex("300a06082a8648ce3d040302")
  assert_eq(
    parse_outcome({ ..parts, algorithm: sha256 }.join()),
    "the two signature algorithms differ",
  )
  let other_inner = parts.fields.copy()
  other_inner[2] = sha256
  assert_eq(
    parse_outcome({ ..parts, fields: other_inner }.join()),
    "the two signature algorithms differ",
  )
  let with_null = hex("300c06082a8648ce3d0403030500")
  assert_eq(
    parse_outcome({ ..parts, algorithm: with_null }.join()),
    "the two signature algorithms differ",
  )
  // The same NULL parameters on both sides are read.
  let both_null = parts.fields.copy()
  both_null[2] = with_null
  assert_eq(
    parse_outcome({ fields: both_null, algorithm: with_null, signature: parts.signature }.join()),
    "ok",
  )
  // The signature BIT STRING has unused bits.
  let unused = parts.signature.to_array()
  unused[2] = b'\x01'
  assert_true(
    parse_outcome({ ..parts, signature: Bytes::from_array(unused) }.join()).has_prefix(
      "malformed DER",
    ),
  )
}

///|
test "extension rules" {
  let parts = split(github_leaf(morphir_bundle))
  let extensions = parts.extensions()
  // A repeated extension.
  let repeated = extensions.copy()
  repeated.push(extensions[0])
  assert_eq(
    parse_outcome(parts.with_extensions(repeated).join()),
    "the extension 2.5.29.15 is repeated",
  )
  // DER omits critical=false.
  let explicit_false = extensions.copy()
  explicit_false.push(extension("2a0304", Some("00"), b"\x05\x00"))
  assert_eq(
    parse_outcome(parts.with_extensions(explicit_false).join()),
    "critical is encoded as false",
  )
  // A BOOLEAN that is not 0x00 or 0xff.
  let not_der = extensions.copy()
  not_der.push(extension("2a0304", Some("01"), b"\x05\x00"))
  assert_true(
    parse_outcome(parts.with_extensions(not_der).join()).has_prefix("malformed DER"),
  )
  // A known extension whose value is not its type.
  let bad_key_usage = extensions.copy()
  bad_key_usage[0] = extension("551d0f", Some("ff"), b"\x04\x00")
  assert_true(
    parse_outcome(parts.with_extensions(bad_key_usage).join()).has_prefix("malformed DER"),
  )
  // A SAN URI that is not printable ASCII.
  let bad_san = extensions.map(raw => if oid_of(raw) == "2.5.29.17" {
    extension("551d11", Some("ff"), b"\x30\x03\x86\x01\x0a")
  } else {
    raw
  })
  assert_eq(
    parse_outcome(parts.with_extensions(bad_san).join()),
    "a name is not printable ASCII",
  )
}

///|
test "unhandled_critical names an unknown critical extension" {
  let parts = split(github_leaf(morphir_bundle))
  let leaf = @x509.parse(parts.with_extensions(parts.extensions()).join())
  assert_eq(leaf.unhandled_critical(), None)
  // 1.2.3.4, critical and not critical.
  let critical = parts.extensions()
  critical.push(extension("2a0304", Some("ff"), b"\x05\x00"))
  let marked = @x509.parse(parts.with_extensions(critical).join())
  assert_eq(marked.unhandled_critical(), Some("1.2.3.4"))
  assert_eq(marked.unhandled_critical(allowed=["1.2.3.4"]), None)
  assert_eq(marked.unhandled_critical(allowed=["1.2.3.5"]), Some("1.2.3.4"))
  guard marked.extension("1.2.3.4") is Some(added) else { fail("no 1.2.3.4") }
  assert_true(added.critical)
  assert_eq(added.value, b"\x05\x00")
  let plain = parts.extensions()
  plain.push(extension("2a0304", None, b"\x05\x00"))
  let unmarked = @x509.parse(parts.with_extensions(plain).join())
  assert_eq(unmarked.unhandled_critical(), None)
  guard unmarked.extension("1.2.3.4") is Some(added) else { fail("no 1.2.3.4") }
  assert_false(added.critical)
  // A known critical extension (SAN) is handled.
  guard unmarked.extension("2.5.29.17") is Some(san) else { fail("no SAN") }
  assert_true(san.critical)
}
