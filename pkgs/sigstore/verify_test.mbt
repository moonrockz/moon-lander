///|
/// The finos/morphir-rust case of `cases.json`.
fn morphir_case() -> GitHubCase raise {
  for case in github_cases() {
    if case.bundle == morphir_bundle {
      return case
    }
  }
  fail("no morphir-rust case")
}

///|
/// The morphir-rust policy of `cases.json`: its signer workflow and source
/// repository, on a GitHub-hosted runner.
fn morphir_policy() -> @sigstore.Policy raise {
  case_policy(morphir_case())
}

///|
/// Verify a changed morphir-rust bundle document.
fn verify_document(
  doc : Json,
  policy : @sigstore.Policy,
  root? : @sigstore.TrustedRoot = @sigstore.TrustedRoot::public_good(),
  now? : @sigstore.Instant = later,
  digest? : String = morphir_digest,
  alternatives? : Array[@sigstore.Policy] = [],
) -> @sigstore.Verdict raise {
  @sigstore.verify(
    @sigstore.Bundle::parse(doc.stringify()),
    @sigstore.ArtifactDigest::parse(digest),
    root,
    policy,
    now~,
    alternatives~,
  )
}

///|
/// Verify the unchanged morphir-rust bundle.
fn verify_morphir(
  policy : @sigstore.Policy,
  root? : @sigstore.TrustedRoot = @sigstore.TrustedRoot::public_good(),
  now? : @sigstore.Instant = later,
  digest? : String = morphir_digest,
  alternatives? : Array[@sigstore.Policy] = [],
) -> @sigstore.Verdict raise {
  verify_document(morphir_document(), policy, root~, now~, digest~, alternatives~)
}

///|
/// The outcome of a changed conformance bundle, with the artifact, identity,
/// issuer and trusted root of its case.
fn verify_conformance_document(
  name : String,
  doc : Json,
  now? : @sigstore.Instant = later,
) -> String raise {
  let artifact = match case_file(name, "artifact") {
    Some(text) => text
    None => fixture(@fixtures.conformance, "a.txt")
  }
  let identity = case_file(name, "identity")
    .unwrap_or(default_identity)
    .trim(char_set=" \n")
    .to_owned()
  let issuer = case_file(name, "issuer")
    .unwrap_or(default_issuer)
    .trim(char_set=" \n")
    .to_owned()
  let root = match case_file(name, "trusted_root.json") {
    Some(text) => @sigstore.TrustedRoot::parse(text)
    None => @sigstore.TrustedRoot::public_good()
  }
  outcome(
    @sigstore.verify(
      @sigstore.Bundle::parse(doc.stringify()),
      @sigstore.ArtifactDigest::of_bytes(@utf8.encode(artifact)),
      root,
      @sigstore.Policy::subject_name(
        @sigstore.SubjectName::parse(identity),
        issuer=@sigstore.Issuer::parse(issuer),
      ),
      now~,
    ),
  )
}

///|
/// The public-good trusted root document with one change.
fn changed_root(change : (Json) -> Unit raise) -> @sigstore.TrustedRoot raise {
  let doc = @json.parse(@sigstore.public_good_trusted_root_json())
  change(doc)
  @sigstore.TrustedRoot::parse(doc.stringify())
}

///|
let entry_path : String = "verificationMaterial.tlogEntries.0"

///|
let proof_path : String = "verificationMaterial.tlogEntries.0.inclusionProof"

///|
/// The checkpoint text with one bit of the log signature changed. The key
/// hint, the first 4 bytes, stays the same.
fn flip_checkpoint_signature(envelope : String) -> String raise {
  let lines = envelope.split("\n").map(line => line.to_owned()).collect()
  guard lines.search_by(line => line.has_prefix("\u{2014} ")) is Some(index) else {
    fail("no signature line")
  }
  let words = lines[index].split(" ").map(word => word.to_owned()).collect()
  words[words.length() - 1] = flip_base64(words[words.length() - 1], 10)
  lines[index] = words.join(" ")
  lines.join("\n")
}

///|
test "scenario: pass" {
  let verdict = verify_morphir(morphir_policy())
  guard verdict is Verified(facts) else { fail(outcome(verdict)) }
  guard facts.statement is Some(statement) else { fail("no statement") }
  assert_eq(statement.predicate_type, "https://slsa.dev/provenance/v1")
  assert_eq(statement.subjects.length(), 4)
  assert_eq(
    statement.subjects[0].sha256.map(digest => digest.to_string()),
    Some(
      "sha256:03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd",
    ),
  )
  assert_eq(facts.integrated_time.unix_seconds(), 1792133282L)
  assert_eq(facts.claims.subject_names, [
    "https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/tags/provider-snapshot/v0.2.0",
  ])
  assert_eq(facts.policy_index, 0)
  assert_eq(facts.log_index, 3275146211L)
  assert_eq(
    facts.log_id,
    @encoding.decode_base64("wNI9atQGlz+VWfO6LRygH4QUfY/8W4RFwiT5i5WRgB0="),
  )
  assert_eq(facts.claims.issuer, Some("https://token.actions.githubusercontent.com"))
  assert_eq(facts.claims.source_repository_uri, Some("https://github.com/finos/morphir-rust"))
  assert_eq(facts.claims.source_repository_identifier, Some("513894754"))
  assert_eq(facts.claims.source_repository_owner_identifier, Some("35377814"))
  assert_eq(facts.claims.source_repository_ref, Some("refs/tags/provider-snapshot/v0.2.0"))
  assert_eq(facts.claims.runner_environment, Some("github-hosted"))
}

///|
test "scenario: not supported" {
  let name = "rekor2-happy-path"
  let root = @sigstore.TrustedRoot::parse(fixture(@fixtures.conformance, "\{name}/trusted_root.json"))
  let doc = conformance_document(name)
  assert_true(find(doc, "verificationMaterial.timestampVerificationData.rfc3161Timestamps.0") is Object(_))
  let verdict = @sigstore.verify(
    @sigstore.Bundle::parse(doc.stringify()),
    @sigstore.ArtifactDigest::of_bytes(@utf8.encode(fixture(@fixtures.conformance, "a.txt"))),
    root,
    @sigstore.Policy::subject_name(
      @sigstore.SubjectName::parse(default_identity),
      issuer=@sigstore.Issuer::parse(default_issuer),
    ),
    now=later,
  )
  guard verdict is Rejected(Unsupported(RekorV2) as rejection) else { fail(outcome(verdict)) }
  assert_true(rejection.message() != "")
}

///|
test "scenario: subject in a multi-subject statement" {
  let third = "sha256:2696a72d7096a3d1285589a46f2dcbeaf84859e9c5cefa09422cad4f016a786c"
  let verdict = verify_morphir(morphir_policy(), digest=third)
  guard verdict is Verified(facts) else { fail(outcome(verdict)) }
  guard facts.statement is Some(statement) else { fail("no statement") }
  assert_eq(statement.subjects[2].name, "morphir-provider-snapshot")
  // The hex digest compares without regard to letter case.
  let upper = "sha256:" + third["sha256:".length():].to_owned().to_upper()
  assert_eq(outcome(verify_morphir(morphir_policy(), digest=upper)), "pass")
}

///|
test "scenario: other artifact" {
  let other = "sha256:" + repeat('0', 64)
  let verdict = verify_morphir(morphir_policy(), digest=other)
  guard verdict is Rejected(Invalid(ArtifactDigestMismatch(digest))) else {
    fail(outcome(verdict))
  }
  assert_eq(digest, @sigstore.ArtifactDigest::parse(other))
}

///|
test "scenario: changed payload" {
  let doc = morphir_document()
  set_field(doc, "dsseEnvelope", "payload", Json::string(flip_base64(text_at(doc, "dsseEnvelope.payload"), 40)))
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Invalid(TransparencyLogBody(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the payload hash differs from the payload")
}

///|
test "scenario: two signatures" {
  let doc = morphir_document()
  let signatures = array_at(doc, "dsseEnvelope.signatures")
  signatures.push(copy_json(signatures[0]))
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Invalid(BundleShape(_))) else { fail(outcome(verdict)) }
  // No signature is a bundle shape failure too.
  signatures.clear()
  assert_eq(outcome(verify_document(doc, morphir_policy())), "bundle shape")
}

///|
test "scenario: untrusted root" {
  // The leaf chains to the public-good Fulcio; the root lists only the mock
  // certificate authority of a conformance case.
  let custom = @json.parse(
    fixture(@fixtures.conformance, "intoto-with-custom-trust-root/trusted_root.json"),
  )
  let root = changed_root(doc => set_field(
    doc,
    "",
    "certificateAuthorities",
    find(custom, "certificateAuthorities"),
  ))
  assert_eq(root.summary().certificate_authorities, ["http://localhost:8000"])
  let verdict = verify_morphir(morphir_policy(), root~)
  guard verdict is Rejected(Invalid(CertificateChain(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "no certificate of the authority issued the leaf")
  // A root with no certificate authority.
  let empty = changed_root(doc => set_field(doc, "", "certificateAuthorities", Json::array([])))
  assert_eq(outcome(verify_morphir(morphir_policy(), root=empty)), "certificate chain")
  // Only the old Fulcio authority, whose validity ends before the log time.
  let old = changed_root(doc => array_at(doc, "certificateAuthorities").truncate(1))
  assert_eq(outcome(verify_morphir(morphir_policy(), root=old)), "certificate chain")
}

///|
test "scenario: leaf expired at log time" {
  let name = "integrated-time-in-future_fail"
  let doc = conformance_document(name)
  let verdict = @sigstore.verify(
    @sigstore.Bundle::parse(doc.stringify()),
    @sigstore.ArtifactDigest::of_bytes(@utf8.encode(fixture(@fixtures.conformance, "a.txt"))),
    @sigstore.TrustedRoot::public_good(),
    @sigstore.Policy::subject_name(
      @sigstore.SubjectName::parse(default_identity),
      issuer=@sigstore.Issuer::parse(default_issuer),
    ),
    now=later,
  )
  guard verdict is Rejected(Invalid(CertificateValidity(not_before~, not_after~, time~))) else {
    fail(outcome(verdict))
  }
  assert_true(not_before <= not_after)
  assert_true(time > not_after, msg="\{time} \{not_after}")
}

///|
test "scenario: unknown CT log" {
  let root = changed_root(doc => set_field(doc, "", "ctlogs", Json::array([])))
  let verdict = verify_morphir(morphir_policy(), root~)
  guard verdict is Rejected(Invalid(CertificateTimestamp(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "no SCT from a trusted CT log verifies")
}

///|
test "scenario: bad signed entry timestamp" {
  let doc = morphir_document()
  let path = "\{entry_path}.inclusionPromise"
  set_field(
    doc,
    path,
    "signedEntryTimestamp",
    Json::string(flip_base64(text_at(doc, "\{path}.signedEntryTimestamp"), 50)),
  )
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Invalid(TransparencyLog(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the signed entry timestamp does not verify")
}

///|
test "scenario: integrated time in the future" {
  let integrated = @sigstore.Instant::from_unix_seconds(1792133282L)
  let before = @sigstore.Instant::from_unix_seconds(1792133281L)
  let verdict = verify_morphir(morphir_policy(), now=before)
  guard verdict is Rejected(Invalid(TransparencyLogTime(integrated_time~, now~))) else {
    fail(outcome(verdict))
  }
  assert_eq(integrated_time, integrated)
  assert_eq(now, before)
  // "now" equal to the integrated time is not in the future.
  assert_eq(outcome(verify_morphir(morphir_policy(), now=integrated)), "pass")
}

///|
test "scenario: body for another signature" {
  let doc = morphir_document()
  let path = "dsseEnvelope.signatures.0"
  set_field(doc, path, "sig", Json::string(flip_base64(text_at(doc, "\{path}.sig"), 20)))
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Invalid(TransparencyLogBody(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the logged signature differs from the envelope")
}

///|
test "scenario: corrupted proof hash" {
  let doc = morphir_document()
  let hashes = array_at(doc, "\{proof_path}.hashes")
  guard hashes[3] is String(hash) else { fail("not a string") }
  hashes[3] = Json::string(flip_base64(hash, 0))
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Invalid(InclusionProof(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the proof gives another root hash")
  // One hash fewer does not fit the index and tree size.
  let short = morphir_document()
  ignore(array_at(short, "\{proof_path}.hashes").pop())
  assert_eq(outcome(verify_document(short, morphir_policy())), "inclusion proof")
}

///|
test "scenario: checkpoint signed by another key" {
  let doc = morphir_document()
  let path = "\{proof_path}.checkpoint"
  set_field(
    doc,
    path,
    "envelope",
    Json::string(flip_checkpoint_signature(text_at(doc, "\{path}.envelope"))),
  )
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Invalid(Checkpoint(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "no signature of the log key verifies")
}

///|
test "scenario: real sharded log entry" {
  let doc = morphir_document()
  assert_eq(text_at(doc, "\{entry_path}.logIndex"), "3275146211")
  assert_eq(text_at(doc, "\{proof_path}.logIndex"), "3153241949")
  assert_eq(outcome(verify_document(doc, morphir_policy())), "pass")
  // The entry index in the proof does not give the root hash.
  set_field(doc, proof_path, "logIndex", Json::string("3275146211"))
  assert_eq(outcome(verify_document(doc, morphir_policy())), "inclusion proof")
}

///|
/// The log ID of the Ed25519 `log2025-1` log of the public-good root.
fn ed25519_log_id() -> String raise {
  let root = @json.parse(@sigstore.public_good_trusted_root_json())
  for log in array_at(root, "tlogs") {
    if text_at(log, "baseUrl") == "https://log2025-1.rekor.sigstore.dev" {
      return text_at(log, "logId.keyId")
    }
  }
  fail("no log2025-1")
}

///|
test "one mutation for each step of the pipeline" {
  let ed25519 = ed25519_log_id()
  let cases : Array[(String, (Json) -> Unit raise, String)] = [
    ("unchanged", _ => (), "pass"),
    (
      "public key material",
      doc => {
        remove_field(doc, "verificationMaterial", "certificate")
        set_field(doc, "verificationMaterial", "publicKey", Json::object({ "hint": Json::string("a") }))
      },
      "unsupported public key",
    ),
    (
      "no log entry",
      doc => array_at(doc, "verificationMaterial.tlogEntries").clear(),
      "transparency log",
    ),
    (
      "no log entry, a timestamp",
      doc => {
        array_at(doc, "verificationMaterial.tlogEntries").clear()
        set_field(
          doc,
          "verificationMaterial",
          "timestampVerificationData",
          Json::object({
            "rfc3161Timestamps": Json::array([
              Json::object({ "signedTimestamp": Json::string("AAAA") }),
            ]),
          }),
        )
      },
      "unsupported timestamp authority",
    ),
    (
      "two signatures",
      doc => {
        let signatures = array_at(doc, "dsseEnvelope.signatures")
        signatures.push(copy_json(signatures[0]))
      },
      "bundle shape",
    ),
    (
      "leaf that is not a certificate",
      doc => set_field(doc, "verificationMaterial.certificate", "rawBytes", Json::string("AAAA")),
      "certificate",
    ),
    (
      "Rekor v2 entry",
      doc => set_field(doc, "\{entry_path}.kindVersion", "version", Json::string("0.0.2")),
      "unsupported Rekor v2",
    ),
    (
      "intoto entry",
      doc => set_field(doc, "\{entry_path}.kindVersion", "kind", Json::string("intoto")),
      "unsupported entry kind",
    ),
    (
      "log not in the root",
      doc => set_field(
        doc,
        "\{entry_path}.logId",
        "keyId",
        Json::string(flip_base64(text_at(doc, "\{entry_path}.logId.keyId"), 0)),
      ),
      "transparency log",
    ),
    (
      "Ed25519 log",
      doc => set_field(doc, "\{entry_path}.logId", "keyId", Json::string(ed25519)),
      "unsupported key type",
    ),
    (
      "no signed entry timestamp",
      doc => remove_field(doc, entry_path, "inclusionPromise"),
      "transparency log",
    ),
    (
      "bad signed entry timestamp",
      doc => set_field(
        doc,
        "\{entry_path}.inclusionPromise",
        "signedEntryTimestamp",
        Json::string(
          flip_base64(text_at(doc, "\{entry_path}.inclusionPromise.signedEntryTimestamp"), 50),
        ),
      ),
      "transparency log",
    ),
    (
      "body changed",
      doc => set_field(
        doc,
        entry_path,
        "canonicalizedBody",
        Json::string(flip_base64(text_at(doc, "\{entry_path}.canonicalizedBody"), 30)),
      ),
      "transparency log",
    ),
    (
      "corrupted proof hash",
      doc => {
        let hashes = array_at(doc, "\{proof_path}.hashes")
        hashes[0] = Json::string(flip_base64(text_at(doc, "\{proof_path}.hashes.0"), 5))
      },
      "inclusion proof",
    ),
    (
      "root hash of the proof and checkpoint changed",
      doc => set_field(
        doc,
        proof_path,
        "rootHash",
        Json::string(flip_base64(text_at(doc, "\{proof_path}.rootHash"), 5)),
      ),
      "inclusion proof",
    ),
    (
      "checkpoint signature",
      doc => set_field(
        doc,
        "\{proof_path}.checkpoint",
        "envelope",
        Json::string(flip_checkpoint_signature(text_at(doc, "\{proof_path}.checkpoint.envelope"))),
      ),
      "checkpoint",
    ),
    (
      "checkpoint without a signature",
      doc => set_field(
        doc,
        "\{proof_path}.checkpoint",
        "envelope",
        Json::string("rekor.sigstore.dev - 1193050959916656506\n3153242266\nx\n"),
      ),
      "checkpoint",
    ),
    (
      "payload changed",
      doc => set_field(
        doc,
        "dsseEnvelope",
        "payload",
        Json::string(flip_base64(text_at(doc, "dsseEnvelope.payload"), 40)),
      ),
      "transparency log body",
    ),
    (
      "envelope signature changed",
      doc => set_field(
        doc,
        "dsseEnvelope.signatures.0",
        "sig",
        Json::string(flip_base64(text_at(doc, "dsseEnvelope.signatures.0.sig"), 20)),
      ),
      "transparency log body",
    ),
    (
      "payload type changed",
      doc => set_field(doc, "dsseEnvelope", "payloadType", Json::string("application/json")),
      "payload type",
    ),
  ]
  for case in cases {
    let doc = morphir_document()
    (case.1)(doc)
    assert_eq(outcome(verify_document(doc, morphir_policy())), case.2, msg=case.0)
  }
  let digest = "sha256:" + repeat('1', 64)
  assert_eq(outcome(verify_morphir(morphir_policy(), digest~)), "artifact digest")
  let other = @sigstore.Policy::github_workflow(
    @sigstore.GitHubRepository::parse("finos/morphir-ui"),
    workflow=@sigstore.WorkflowPath::parse(morphir_case().workflow),
  )
  assert_eq(outcome(verify_morphir(other)), "policy")
  let no_ctlogs = changed_root(doc => set_field(doc, "", "ctlogs", Json::array([])))
  assert_eq(outcome(verify_morphir(morphir_policy(), root=no_ctlogs)), "certificate timestamp")
  let no_cas = changed_root(doc => set_field(doc, "", "certificateAuthorities", Json::array([])))
  assert_eq(outcome(verify_morphir(morphir_policy(), root=no_cas)), "certificate chain")
  let no_tlogs = changed_root(doc => array_at(doc, "tlogs").truncate(1))
  assert_eq(outcome(verify_morphir(morphir_policy(), root=no_tlogs)), "pass")
  let early = @sigstore.Instant::from_unix_seconds(1792133281L)
  assert_eq(outcome(verify_morphir(morphir_policy(), now=early)), "transparency log time")
}

///|
test "a log entry from the Ed25519 log is not supported" {
  let doc = morphir_document()
  set_field(doc, "\{entry_path}.logId", "keyId", Json::string(ed25519_log_id()))
  let verdict = verify_document(doc, morphir_policy())
  guard verdict is Rejected(Unsupported(KeyType(_))) else { fail(outcome(verdict)) }
}

///|
test "scenario: offline after install" {
  for case in github_cases() {
    let policy = case_policy(case)
    let first = verify_case(case, policy)
    assert_true(first is Verified(_), msg=case.bundle)
    assert_eq(verify_case(case, policy), first, msg=case.bundle)
    let bundle = @sigstore.Bundle::parse(fixture(@fixtures.github, case.bundle))
    let digest = @sigstore.ArtifactDigest::parse(case.digest)
    let root = @sigstore.TrustedRoot::public_good()
    for seconds in [case.integrated_time, 1793000000L, 2000000000L, 4102444800L] {
      let verdict = @sigstore.verify(
        bundle,
        digest,
        root,
        policy,
        now=@sigstore.Instant::from_unix_seconds(seconds),
      )
      assert_eq(verdict, first, msg="\{case.bundle} at \{seconds}")
    }
  }
}

///|
test "the same inputs give the same rejection" {
  let digest = "sha256:" + repeat('0', 64)
  let first = verify_morphir(morphir_policy(), digest~)
  assert_eq(verify_morphir(morphir_policy(), digest~), first)
  let much_later = @sigstore.Instant::from_unix_seconds(4102444800L)
  assert_eq(verify_morphir(morphir_policy(), digest~, now=much_later), first)
}
