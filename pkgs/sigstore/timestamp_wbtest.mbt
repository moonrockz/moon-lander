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
  let as_leaf : Authority = { uri: "test", chain: self_signed, valid: open, source: 0 }
  assert_true(timestamp_signer(token, as_leaf, time) is Some(_))
}

///|
test "the SCT rule follows the root that listed each authority" {
  let combined = TrustedRoot::github_attestations()
  let flags = combined.authorities.map(authority => combined.lists_ctlogs(authority.source))
  // Public good has two CAs and CT logs; GitHub has six CAs and none.
  assert_eq(flags, [true, true, false, false, false, false, false, false])
  assert_eq(combined.authorities.map(authority => combined.lists_tlogs(authority.source)), flags)
  // Combining a combined root keeps each source apart.
  let twice = TrustedRoot::combine([combined, TrustedRoot::github()])
  assert_eq(twice.authorities.map(authority => authority.source), [0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2])
  assert_eq(combined.timestamp_authorities.length(), 7)
}

///|
test "a leaf is checked at the timestamp time" {
  let bundle = release_bundle()
  guard bundle.material is Certificate(raw) else { fail("no certificate") }
  let leaf = read_leaf(raw) catch { Stop(_) => fail("leaf") }
  let after = Instant::from_unix_seconds(leaf.certificate.not_after + 1L)
  let failure = try {
    ignore(check_certificate(leaf, TrustedRoot::github(), after))
    None
  } catch {
    Stop(rejection) => Some(rejection)
  }
  assert_true(failure is Some(Invalid(CertificateValidity(..))))
  let inside = Instant::from_unix_seconds(leaf.certificate.not_after)
  assert_true(
    (try {
      ignore(check_certificate(leaf, TrustedRoot::github(), inside))
      true
    } catch {
      Stop(_) => false
    }),
  )
  // A fraction of a second after the last valid second is outside.
  assert_false(valid_at(leaf.certificate, Instant::from_parts(leaf.certificate.not_after, 1)))
}

///|
fn concat(parts : Array[BytesView]) -> Bytes {
  let out : Array[Byte] = []
  for part in parts {
    for byte in part {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
/// The TimeStampResp with its SignedData `certificates` replaced. The set is
/// outside the signed attributes, so the signature stays valid.
fn with_certificates(response : Bytes, certificates : Array[Bytes]) -> Bytes raise {
  let outer = @der.parse_tag(response, @der.SEQUENCE).children()
  let status = outer.next()
  let content_info = outer.next().children()
  let oid = content_info.next()
  let signed_data = content_info.next().children().next().children()
  let head = [signed_data.next().raw, signed_data.next().raw, signed_data.next().raw]
  let rest = []
  while !signed_data.is_empty() {
    let element = signed_data.next()
    if element.tag != @der.context(0) {
      rest.push(element.raw)
    }
  }
  let certificate_set = @der.encode(@der.context(0), concat(certificates.map(c => c[:])))
  let body = @der.encode(@der.SEQUENCE, concat([..head, certificate_set[:], ..rest]))
  let info = @der.encode(@der.SEQUENCE, concat([oid.raw, @der.encode(@der.context(0), body)[:]]))
  @der.encode(@der.SEQUENCE, concat([status.raw, info[:]]))
}

///|
/// The GitHub timestamp authority that signed the release token.
fn release_authority(token : @timestamp.Timestamp) -> Authority {
  TrustedRoot::github()
  .timestamp_authorities
  .iter()
  .find_first(authority => {
    let leaf = authority.chain[0]
    leaf.issuer == token.signer_issuer && leaf.serial == token.signer_serial
  })
  .unwrap()
}

///|
test "a CA-only authority takes the signer from the token" {
  let response = release_bundle().timestamps[0]
  let token = @timestamp.parse(response)
  let authority = release_authority(token)
  let time = Instant::from_parts(token.seconds, token.nanos)
  let ca_only = { ..authority, chain: authority.chain[1:].to_owned() }
  // Without an embedded certificate there is no signer.
  assert_eq(timestamp_signer(token, ca_only, time), Some("the token has no certificate for its signer"))
  // With the leaf embedded, the signer chains to the authority.
  let leaf = authority.chain[0].raw
  let embedded = @timestamp.parse(with_certificates(response, [leaf]))
  assert_eq(embedded.certificates.length(), 1)
  assert_eq(timestamp_signer(embedded, ca_only, time), None)
  assert_true(embedded.verify_signature(@signature.PublicKey::from_spki(authority.chain[0].spki)))
  // Another authority's leaf does not name the signer.
  let others = TrustedRoot::github().timestamp_authorities.filter(other => other.chain[0].raw != leaf)
  let other_leaf = @timestamp.parse(with_certificates(response, [others[0].chain[0].raw]))
  assert_eq(timestamp_signer(other_leaf, ca_only, time), Some("the token has no certificate for its signer"))
  // The right leaf with the chain of another instance's authority does not chain.
  let public = TrustedRoot::public_good().timestamp_authorities[0]
  let other_ca = { ..public, chain: public.chain[1:].to_owned(), valid: { start: None, end: None } }
  assert_eq(timestamp_signer(embedded, other_ca, time), Some("no certificate of the authority issued the leaf"))
  // With a listed leaf, an embedded certificate is never the signer: the
  // trusted leaf still decides.
  assert_eq(timestamp_signer(other_leaf, authority, time), None)
}

///|
/// The response with the first occurrence of `pattern` after `from` changed.
fn change_after(response : Bytes, pattern : Bytes, from~ : Int = 0) -> (Bytes, Int) {
  let bytes = response.to_array()
  for i in from..<(bytes.length() - pattern.length()) {
    if Bytes::from_array(bytes[i:i + pattern.length()]) == pattern {
      let last = i + pattern.length() - 1
      bytes[last] = bytes[last] ^ 1
      return (Bytes::from_array(bytes), i)
    }
  }
  abort("pattern not found")
}

///|
test "the signed attributes must name the TSTInfo and the signer" {
  let response = release_bundle().timestamps[0]
  let token = @timestamp.parse(response)
  let authority = release_authority(token)
  let time = Instant::from_parts(token.seconds, token.nanos)
  // The signingCertificateV2 hash is the SHA-256 of the signer.
  let (changed_hash, _) = change_after(response, @signature.sha256(authority.chain[0].raw))
  assert_eq(
    timestamp_signer(@timestamp.parse(changed_hash), authority, time),
    Some("the signing certificate attribute names another certificate"),
  )
  // id-ct-TSTInfo is the encapsulated content type, and then the content type
  // attribute; a changed attribute value is refused.
  let oid = b"\x06\x0b\x2a\x86\x48\x86\xf7\x0d\x01\x09\x10\x01\x04"
  let (_, first) = change_after(response, oid)
  let (changed_type, _) = change_after(response, oid, from=first + 1)
  let refused = try {
    ignore(@timestamp.parse(changed_type))
    None
  } catch {
    BadTimestamp(rule) => Some(rule)
    _ => None
  }
  assert_eq(refused, Some("the content type attribute is not id-ct-TSTInfo"))
}
