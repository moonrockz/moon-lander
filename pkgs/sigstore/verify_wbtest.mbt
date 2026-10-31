///|
fn group_file(group : Array[(String, String)], path : String) -> String raise {
  match group.iter().find_first(file => file.0 == path) {
    Some(file) => file.1
    None => fail("no fixture \{path}")
  }
}

///|
/// The bytes with one bit of byte `index` changed.
fn flip_byte(bytes : Bytes, index : Int) -> Bytes {
  let array = bytes.to_array()
  array[index] = (array[index].to_int() ^ 1).to_byte()
  Bytes::from_array(array)
}

///|
/// A parsed fixture bundle and its leaf.
fn bundle_and_leaf(text : String) -> (Bundle, Leaf) raise {
  let bundle = Bundle::parse(text)
  guard bundle.material is Certificate(raw) else { fail("no certificate") }
  let leaf = read_leaf(raw) catch { Stop(_) => fail("the leaf does not parse") }
  (bundle, leaf)
}

///|
fn morphir_parts() -> (Bundle, Leaf) raise {
  bundle_and_leaf(group_file(@fixtures.github, "morphir-rust-provider-snapshot-0.2.0.sigstore.json"))
}

///|
let morphir_artifact : String = "sha256:03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd"

///|
/// The rejection of a pipeline step, or `None` when it passes.
fn step_rejection(step : () -> Unit raise Stop) -> Rejection? {
  try step() catch {
    Stop(rejection) => Some(rejection)
  } noraise {
    _ => None
  }
}

///|
fn with_signature(bundle : Bundle, signature : Bytes) -> Bundle {
  match bundle.content {
    Dsse(envelope) => { ..bundle, content: Dsse({ ..envelope, signatures: [signature] }) }
    Message(algorithm~, digest~, ..) => { ..bundle, content: Message(algorithm~, digest~, signature~) }
  }
}

///|
test "scenario: signature that does not verify" {
  let (bundle, leaf) = morphir_parts()
  let artifact = ArtifactDigest::parse(morphir_artifact)
  // The unchanged bundle passes the content check.
  guard check_content(bundle, leaf, artifact) is Some(statement) else { fail("no statement") }
  assert_eq(statement.subjects.length(), 4)
  guard bundle.content is Dsse(envelope) else { fail("not DSSE") }
  let signature = envelope.signatures[0]
  // One bit of the last byte of the DER signature changes; the log body check is
  // not run, so the content check sees the changed signature.
  let changed = with_signature(bundle, flip_byte(signature, signature.length() - 1))
  assert_eq(
    step_rejection(() => ignore(check_content(changed, leaf, artifact))),
    Some(Invalid(ContentSignature)),
  )
  // A valid signature of another bundle by another key.
  let (other, _) = bundle_and_leaf(group_file(@fixtures.github, "cli-2.83.0.sigstore.json"))
  guard other.content is Dsse(other_envelope) else { fail("not DSSE") }
  let foreign = with_signature(bundle, other_envelope.signatures[0])
  assert_eq(
    step_rejection(() => ignore(check_content(foreign, leaf, artifact))),
    Some(Invalid(ContentSignature)),
  )
  // A changed payload with the original signature.
  let payload = { ..bundle, content: Dsse({ ..envelope, payload: flip_byte(envelope.payload, 40) }) }
  assert_eq(
    step_rejection(() => ignore(check_content(payload, leaf, artifact))),
    Some(Invalid(ContentSignature)),
  )
  // Another payload type is refused before the signature check.
  let payload_type = {
    ..bundle,
    content: Dsse({ ..envelope, payload_type: "application/vnd.in-toto+json; charset=utf-8" }),
  }
  assert_eq(
    step_rejection(() => ignore(check_content(payload_type, leaf, artifact))),
    Some(Invalid(PayloadType("application/vnd.in-toto+json; charset=utf-8"))),
  )
}

///|
test "message signature content checks" {
  let name = "happy-path-v0.3"
  let (bundle, leaf) = bundle_and_leaf(
    group_file(@fixtures.conformance, "\{name}/bundle.sigstore.json"),
  )
  let artifact = ArtifactDigest::of_bytes(
    @utf8.encode(group_file(@fixtures.conformance, "a.txt")),
  )
  assert_eq(step_rejection(() => ignore(check_content(bundle, leaf, artifact))), None)
  guard bundle.content is Message(algorithm~, digest~, signature~) else {
    fail("not a message signature")
  }
  let changed = with_signature(bundle, flip_byte(signature, signature.length() - 1))
  assert_eq(
    step_rejection(() => ignore(check_content(changed, leaf, artifact))),
    Some(Invalid(ContentSignature)),
  )
  let other = ArtifactDigest::of_bytes(b"other")
  assert_eq(
    step_rejection(() => ignore(check_content(bundle, leaf, other))),
    Some(Invalid(ArtifactDigestMismatch(other))),
  )
  let sha384 = { ..bundle, content: Message(algorithm=Sha2_384, digest~, signature~) }
  assert_eq(
    step_rejection(() => ignore(check_content(sha384, leaf, artifact))),
    Some(Unsupported(DigestAlgorithm("SHA2_384"))),
  )
  assert_true(algorithm is Sha2_256)
  let short = {
    ..bundle,
    content: Message(algorithm~, digest=Bytes::from_array(digest.to_array()[:31].to_owned()), signature~),
  }
  assert_true(
    step_rejection(() => ignore(check_content(short, leaf, artifact))) is
    Some(Invalid(BundleShape(_))),
  )
}

///|
test "scenario: leaf expired at log time (certificate validity bounds)" {
  let (_, leaf) = morphir_parts()
  let root = TrustedRoot::public_good()
  let not_before = leaf.certificate.not_before
  let not_after = leaf.certificate.not_after
  assert_true(not_before <= 1792133282L && 1792133282L <= not_after)
  fn at(seconds : Int64) -> Rejection? {
    step_rejection(() => check_certificate(leaf, root, Instant::from_unix_seconds(seconds)))
  }

  // Both bounds are inclusive.
  assert_eq(at(not_before), None)
  assert_eq(at(not_after), None)
  let validity = fn(seconds : Int64) -> Rejection? {
    Some(
      Invalid(
        CertificateValidity(
          not_before=Instant::from_unix_seconds(not_before),
          not_after=Instant::from_unix_seconds(not_after),
          time=Instant::from_unix_seconds(seconds),
        ),
      ),
    )
  }
  assert_eq(at(not_after + 1L), validity(not_after + 1L))
  assert_eq(at(not_before - 1L), validity(not_before - 1L))
}

///|
test "read_statement refuses a payload that is not a statement" {
  fn reason(payload : String) -> Rejection? {
    step_rejection(() => ignore(read_statement(@encoding.utf8(payload))))
  }

  assert_eq(
    step_rejection(() => ignore(read_statement(b"\xff\xfe"))),
    Some(Invalid(Statement("the payload is not UTF-8"))),
  )
  assert_eq(
    reason("{"),
    Some(Invalid(Statement("the payload is not JSON, or has a duplicate key"))),
  )
  assert_eq(
    reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"subject\":[],\"subject\":[]}"),
    Some(Invalid(Statement("the payload is not JSON, or has a duplicate key"))),
  )
  assert_eq(
    reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"not a uri\",\"subject\":[]}"),
    Some(Invalid(Statement("Invalid predicate type \"not a uri\": use an absolute URI"))),
  )
  assert_eq(
    reason("{\"_type\":\"https://example.com/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[]}"),
    Some(Invalid(Statement("the payload is not an in-toto statement"))),
  )
  assert_eq(
    reason("{\"_type\":\"https://in-toto.io/Statement/v0.1\",\"subject\":[]}"),
    Some(Invalid(Statement("the statement has no predicate type"))),
  )
  assert_true(reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\"}") is Some(Invalid(Statement(_))))
  assert_true(
    reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[{\"name\":\"a\"}]}") is
    Some(Invalid(Statement(_))),
  )
  assert_eq(
    reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[{\"digest\":{\"sha256\":\"zz\"}}]}"),
    Some(Invalid(Statement("a subject digest is not hex"))),
  )
  assert_eq(
    reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[{\"digest\":{\"sha256\":1}}]}"),
    Some(Invalid(Statement("a subject digest is not a string"))),
  )
  assert_eq(
    reason("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[{\"digest\":{\"sha256\":\"\{"ab".repeat(31)}\"}}]}"),
    Some(Invalid(Statement("a subject sha256 digest does not have 32 bytes"))),
  )
  // Upper-case hex is read as lower-case; a subject without sha256 is kept.
  let statement = read_statement(
    @encoding.utf8(
      "{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[{\"name\":\"a\",\"digest\":{\"sha256\":\"ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB\"}},{\"digest\":{\"sha512\":\"00\"}}]}",
    ),
  ) catch {
    Stop(_) => fail("refused")
  }
  assert_eq(statement.subjects.length(), 2)
  assert_eq(statement.subjects[0].name, "a")
  assert_eq(
    statement.subjects[0].sha256.map(digest => digest.to_string()),
    Some("sha256:abababababababababababababababababababababababababababababababab"),
  )
  assert_eq(statement.subjects[1].sha256, None)
}

///|
test "read_statement limits subjects and digests" {
  fn subjects(count : Int, digests : Int) -> Bytes {
    let digest_map = Array::makei(digests, index => "\"d\{index}\":\"00\"").join(",")
    let items = Array::make(count, "{\"digest\":{\{digest_map}}}").join(",")
    @encoding.utf8("{\"_type\":\"https://in-toto.io/Statement/v1\",\"predicateType\":\"https://example.com/p\",\"subject\":[\{items}]}")
  }

  assert_eq(step_rejection(() => ignore(read_statement(subjects(1024, 1)))), None)
  assert_true(
    step_rejection(() => ignore(read_statement(subjects(1025, 1)))) is
    Some(Invalid(Statement(_))),
  )
  assert_eq(step_rejection(() => ignore(read_statement(subjects(1, 32)))), None)
  assert_true(
    step_rejection(() => ignore(read_statement(subjects(1, 33)))) is
    Some(Invalid(Statement(_))),
  )
}

///|
test "an SCT time keeps its milliseconds" {
  let sct = Instant::from_unix_millis(1792133282023L)
  assert_eq(sct.unix_seconds(), 1792133282L)
  // A CT log validity that ends 13 ms before the SCT does not hold it, and
  // one that starts 13 ms after it does not hold it either.
  let end = parse_timestamp("2026-10-16T06:48:02.010Z").unwrap()
  assert_true(end < sct)
  assert_false(({ start: None, end: Some(end) } : Period).contains(sct))
  let start = parse_timestamp("2026-10-16T06:48:02.036Z").unwrap()
  assert_false(({ start: Some(start), end: None } : Period).contains(sct))
  assert_true(({ start: Some(end), end: Some(start) } : Period).contains(sct))
  assert_eq(Instant::from_unix_millis(-1L).unix_seconds(), -1L)
}
