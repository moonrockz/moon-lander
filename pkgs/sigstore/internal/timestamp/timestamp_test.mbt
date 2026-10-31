///|
/// The DER TimeStampResp of the cli/cli v2.103.3 release attestation.
fn release_token() -> Bytes raise {
  let text = @fixtures.github
    .iter()
    .find_first(file => file.0 == "release-cli-2.103.3.sigstore.json")
    .unwrap()
    .1
  guard @json.parse(text) is Object(bundle) &&
    bundle.get("verificationMaterial") is Some(Object(material)) &&
    material.get("timestampVerificationData") is Some(Object(data)) &&
    data.get("rfc3161Timestamps") is Some(Array([Object(token)])) &&
    token.get("signedTimestamp") is Some(String(base64)) else {
    fail("no timestamp")
  }
  @encoding.decode_base64(base64)
}

///|
fn refusal(bytes : Bytes) -> String? {
  try {
    ignore(@timestamp.parse(bytes))
    None
  } catch {
    BadTimestamp(rule) => Some(rule)
    UnsupportedTimestamp(name) => Some("unsupported \{name}")
  }
}

///|
test "the release token gives its fields" {
  let token = @timestamp.parse(release_token())
  assert_eq(token.seconds, 1793042409L)
  assert_eq(token.nanos, 0)
  assert_true(token.imprint_hash is Sha256)
  assert_eq(token.imprint.length(), 32)
  assert_true(token.digest_hash is Sha384)
  assert_true(token.signature_hash is Some(Sha384))
  assert_eq(token.content_type, @timestamp.TST_INFO)
  assert_eq(token.message_digest, @signature.digest(Sha384, token.tst_info))
  assert_true(token.signing_certificate is Some({ hash: Sha256, .. }))
  assert_true(token.signing_time is Some(_))
  // The signature covers the signed attributes as a DER SET.
  assert_eq(token.signed_attributes[0], b'\x31')
  assert_true(token.certificates.is_empty())
  let issuer = @der.parse_tag(token.signer_issuer, @der.SEQUENCE)
  assert_true(issuer.raw.length() > 0)
}

///|
test "truncated, extended or changed responses are refused" {
  let bytes = release_token()
  assert_true(refusal(bytes[:bytes.length() - 1].to_owned()) is Some(_))
  assert_true(refusal(Bytes::from_array([..bytes.to_array(), b'\x00'])) is Some(_))
  assert_true(refusal(b"") is Some(_))
  // The response is not a SEQUENCE.
  let changed = bytes.to_array()
  changed[0] = b'\x31'
  assert_true(refusal(Bytes::from_array(changed)) is Some(_))
}
