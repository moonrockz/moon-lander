///|
/// The error of a trusted root parse, as `field: rule` or `unsupported <type>`;
/// `None` when the parse succeeds.
fn root_error(doc : Json) -> String? {
  try @sigstore.TrustedRoot::parse(doc.stringify()) catch {
    UnsupportedTrustedRootMediaType(media_type) => Some("unsupported \{media_type}")
    InvalidTrustedRoot(field~, rule~) => Some("\{field}: \{rule}")
  } noraise {
    _ => None
  }
}

///|
fn public_good_document() -> Json raise {
  @json.parse(@sigstore.public_good_trusted_root_json())
}

///|
fn key_name(status : @sigstore.KeyStatus) -> String {
  match status {
    Supported => "supported"
    Unsupported(kind) => "unsupported \{kind}"
  }
}

///|
test "scenario: public-good root" {
  let summary = @sigstore.TrustedRoot::public_good().summary()
  assert_eq(
    summary.transparency_logs.map(log => (log.base_url, key_name(log.key))),
    [
      ("https://rekor.sigstore.dev", "supported"),
      ("https://log2025-1.rekor.sigstore.dev", "unsupported Ed25519"),
    ],
  )
  assert_eq(summary.certificate_authorities, [
    "https://fulcio.sigstore.dev", "https://fulcio.sigstore.dev",
  ])
  assert_eq(
    summary.certificate_transparency_logs.map(log => (log.base_url, key_name(log.key))),
    [("https://ctfe.sigstore.dev/test", "supported"), ("https://ctfe.sigstore.dev/2022", "supported")],
  )
  assert_eq(summary.timestamp_authorities, ["https://timestamp.sigstore.dev/api/v1/timestamp"])
}

///|
test "scenario: GitHub root is the pinned public-good root" {
  // The pinned document is the first document of `gh attestation trusted-root`
  // (testdata/README.md); parsing its text gives the same summary.
  let parsed = @sigstore.TrustedRoot::parse(@sigstore.public_good_trusted_root_json()).summary()
  let pinned = @sigstore.TrustedRoot::public_good().summary()
  assert_eq(parsed.certificate_authorities, pinned.certificate_authorities)
  assert_eq(parsed.timestamp_authorities, pinned.timestamp_authorities)
  assert_eq(
    parsed.transparency_logs.map(log => (log.base_url, key_name(log.key))),
    pinned.transparency_logs.map(log => (log.base_url, key_name(log.key))),
  )
}

///|
test "scenario: Ed25519 log in the public-good root" {
  let summary = @sigstore.TrustedRoot::public_good().summary()
  guard summary.transparency_logs.iter().find_first(log => log.base_url == "https://log2025-1.rekor.sigstore.dev")
    is Some(log) else {
    fail("no log2025-1")
  }
  assert_true(log.key is Unsupported(_))
}

///|
test "scenario: pinned digest" {
  assert_eq(
    @sigstore.ArtifactDigest::of_bytes(@utf8.encode(@sigstore.public_good_trusted_root_json())).to_string(),
    "sha256:6494e21ea73fa7ee769f85f57d5a3e6a08725eae1e38c755fc3517c9e6bc0b66",
  )
}

///|
test "scenario: unknown media type" {
  let doc = public_good_document()
  for media_type in [
    "application/vnd.dev.sigstore.trustedroot+json;version=9.9", "application/vnd.dev.sigstore.trustedroot+json;version=0.2",
    "application/json",
  ] {
    set_field(doc, "", "mediaType", Json::string(media_type))
    assert_eq(root_error(doc), Some("unsupported \{media_type}"))
  }
  let err = try @sigstore.TrustedRoot::parse(doc.stringify()) catch {
    err => err
  } noraise {
    _ => fail("parsed")
  }
  assert_eq(err.message(), "Unsupported trusted root media type \"application/json\"")
  remove_field(doc, "", "mediaType")
  assert_eq(root_error(doc), Some("mediaType: field is required"))
}

///|
test "scenario: log without validity start" {
  let doc = public_good_document()
  remove_field(doc, "tlogs.0.publicKey.validFor", "start")
  assert_eq(
    root_error(doc),
    Some("tlogs[0].publicKey.validFor.start: the log https://rekor.sigstore.dev has no validity start"),
  )
  // Without validFor at all.
  let no_period = public_good_document()
  remove_field(no_period, "tlogs.1.publicKey", "validFor")
  assert_eq(
    root_error(no_period),
    Some(
      "tlogs[1].publicKey.validFor.start: the log https://log2025-1.rekor.sigstore.dev has no validity start",
    ),
  )
  // A CT log without a validity start is accepted.
  let ctlog = public_good_document()
  remove_field(ctlog, "ctlogs.0.publicKey.validFor", "start")
  assert_eq(root_error(ctlog), None)
}

///|
test "scenario: bad certificate bytes" {
  let doc = public_good_document()
  set_field(
    doc,
    "certificateAuthorities.1.certChain.certificates.0",
    "rawBytes",
    Json::string(@encoding.encode_base64(b"not a certificate")),
  )
  guard root_error(doc) is Some(error) else { fail("parsed") }
  assert_true(
    error.has_prefix("certificateAuthorities[1].certChain.certificates[0]: "),
    msg=error,
  )
  assert_true(error.has_suffix(" in https://fulcio.sigstore.dev"), msg=error)
  // An empty chain fails too.
  let empty = public_good_document()
  set_field(empty, "certificateAuthorities.0.certChain", "certificates", Json::array([]))
  assert_eq(
    root_error(empty),
    Some("certificateAuthorities[0].certChain.certificates: the chain is empty"),
  )
}

///|
test "trusted root: a bad ECDSA log key and a bad time fail" {
  let key = public_good_document()
  set_field(key, "tlogs.0.publicKey", "rawBytes", Json::string("AAAA"))
  guard root_error(key) is Some(error) else { fail("parsed") }
  assert_true(error.has_prefix("tlogs[0].publicKey.rawBytes: "), msg=error)
  let time = public_good_document()
  set_field(time, "tlogs.0.publicKey.validFor", "start", Json::string("2021-13-01T00:00:00Z"))
  assert_eq(root_error(time), Some("tlogs[0].publicKey.validFor.start: not an RFC 3339 time"))
  let unknown = public_good_document()
  set_field(unknown, "tlogs.0", "extra", Json::null())
  assert_eq(root_error(unknown), Some("tlogs[0].extra: unknown field"))
}

///|
test "trusted root: the log validity end is inclusive" {
  assert_eq(run_case("trust-root-tlog-validity-end-inclusive"), "pass")
  assert_eq(run_case("trust-root-tlog-missing-validity-start_fail"), "parse")
}
