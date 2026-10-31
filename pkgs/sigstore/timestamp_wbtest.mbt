///|
fn release_bundle() -> Bundle {
  let text = @fixtures.github
    .iter()
    .find_first(file => file.0 == "release-cli-2.103.3.sigstore.json")
    .unwrap()
    .1
  Bundle::parse(text) catch {
    err => abort(err.message())
  }
}

///|
test "the pinned GitHub root has six CAs, six TSAs and no log" {
  let summary = TrustedRoot::github().summary()
  assert_eq(summary.certificate_authorities.length(), 6)
  assert_eq(summary.timestamp_authorities.length(), 6)
  assert_true(summary.timestamp_authorities.iter().all(uri => uri == "timestamp.githubapp.com"))
  assert_eq(summary.transparency_logs.length(), 0)
  assert_eq(summary.certificate_transparency_logs.length(), 0)
  assert_eq(
    ArtifactDigest::of_bytes(@encoding.utf8(github_trusted_root_json())).to_string(),
    "sha256:484cdfe1a7c65479c5ba2a22193d1be90f0020db1997de696ab207434c62fbb7",
  )
}

///|
test "the release timestamp gives its time and imprint, and its signature verifies" {
  let bundle = release_bundle()
  assert_eq(bundle.timestamps.length(), 1)
  assert_true(bundle.entries.is_empty())
  let token = @timestamp.parse(bundle.timestamps[0])
  assert_eq(token.seconds, 1793042409L)
  assert_eq(token.nanos, 0)
  assert_true(token.imprint_hash is Sha256)
  guard bundle.content is Dsse(envelope) else { fail("not DSSE") }
  assert_eq(token.imprint, @signature.sha256(envelope.signatures[0]))
  assert_true(token.certificates.is_empty())
  // The signer is the leaf of one GitHub timestamp authority.
  let signers = TrustedRoot::github().timestamp_authorities.filter(authority => {
    let leaf = authority.chain[0]
    leaf.issuer == token.signer_issuer && leaf.serial == token.signer_serial
  })
  assert_eq(signers.length(), 1)
  let key = @signature.PublicKey::from_spki(signers[0].chain[0].spki)
  assert_true(token.verify_signature(key))
  // A changed TSTInfo (one genTime digit) or signature does not verify.
  let response = bundle.timestamps[0].to_array()
  let time = @encoding.utf8("20261026192009Z")
  let mut at = -1
  for i in 0..<(response.length() - time.length()) {
    if Bytes::from_array(response[i:i + time.length()]) == time {
      at = i
      break
    }
  }
  assert_true(at > 0)
  let changed_time = response.copy()
  changed_time[at + 13] = b'8'
  let changed = @timestamp.parse(Bytes::from_array(changed_time))
  assert_eq(changed.seconds, 1793042408L)
  assert_false(changed.verify_signature(key))
  let changed_signature = response.copy()
  let last = changed_signature.length() - 1
  changed_signature[last] = changed_signature[last] ^ 1
  assert_false(@timestamp.parse(Bytes::from_array(changed_signature)).verify_signature(key))
}

///|
test "a TimeStampResp that is not granted is refused" {
  let bundle = release_bundle()
  let bytes = bundle.timestamps[0].to_array()
  // PKIStatusInfo: 30 03 02 01 <status>, at the start of the response.
  guard bytes[4] == b'\x30' && bytes[6] == b'\x02' && bytes[8] == b'\x00' else {
    fail("unexpected response header")
  }
  bytes[8] = b'\x01'
  let refused = try {
    ignore(@timestamp.parse(Bytes::from_array(bytes)))
    false
  } catch {
    BadTimestamp(rule) => rule.contains("not granted")
    _ => false
  }
  assert_true(refused)
}

///|
test "an embedded certificate never becomes the signer" {
  let text = @fixtures.timestamp_authority
    .iter()
    .find_first(file => file.0 == "response-injected-certs.tsr.b64")
    .unwrap()
    .1
  let token = @timestamp.parse(@encoding.decode_base64(text))
  let certificates = token.certificates.map(raw => @x509.parse(raw))
  assert_eq(certificates.length(), 3)
  let self_signed = certificates.filter(certificate => certificate.issuer == certificate.subject)
  assert_eq(self_signed.length(), 1)
  let time = Instant::from_parts(token.seconds, token.nanos)
  let open : Period = { start: None, end: None }
  // The self-signed certificate as the trusted leaf: the token's signer is
  // another certificate, so it is refused.
  let as_leaf : Authority = { uri: "test", chain: self_signed, valid: open, sct_required: false }
  assert_true(timestamp_signer(token, as_leaf, time) is Some(_))
}

///|
test "the SCT rule follows the root that listed each authority" {
  let combined = TrustedRoot::github_attestations()
  let flags = combined.authorities.map(authority => authority.sct_required)
  // Public good has two CAs and CT logs; GitHub has six CAs and none.
  assert_eq(flags, [true, true, false, false, false, false, false, false])
  assert_eq(combined.timestamp_authorities.length(), 7)
}

///|
test "a leaf is checked at the timestamp time" {
  let bundle = release_bundle()
  guard bundle.material is Certificate(raw) else { fail("no certificate") }
  let leaf = read_leaf(raw) catch { Stop(_) => fail("leaf") }
  let after = Instant::from_unix_seconds(leaf.certificate.not_after + 1L)
  let failure = try {
    check_certificate(leaf, TrustedRoot::github(), after)
    None
  } catch {
    Stop(rejection) => Some(rejection)
  }
  assert_true(failure is Some(Invalid(CertificateValidity(..))))
  let inside = Instant::from_unix_seconds(leaf.certificate.not_after)
  assert_true(
    (try {
      check_certificate(leaf, TrustedRoot::github(), inside)
      true
    } catch {
      Stop(_) => false
    }),
  )
  // A fraction of a second after the last valid second is outside.
  assert_false(valid_at(leaf.certificate, Instant::from_parts(leaf.certificate.not_after, 1)))
}
