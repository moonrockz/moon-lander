///|
/// The identity and issuer that the conformance suite uses when a case gives none.
let default_identity : String = "https://github.com/sigstore-conformance/extremely-dangerous-public-oidc-beacon/.github/workflows/extremely-dangerous-oidc-beacon.yml@refs/heads/main"

///|
let default_issuer : String = "https://token.actions.githubusercontent.com"

///|
/// A conformance file of a case, if the case has it.
fn case_file(name : String, file : String) -> String? {
  for entry in @fixtures.conformance {
    if entry.0 == "\{name}/\{file}" {
      return Some(entry.1)
    }
  }
  None
}

///|
/// The names of the conformance cases.
fn conformance_cases() -> Array[String] {
  let names = []
  for entry in @fixtures.conformance {
    if entry.0.has_suffix("/bundle.sigstore.json") {
      names.push(entry.0[:entry.0.length() - "/bundle.sigstore.json".length()].to_owned())
    }
  }
  names
}

///|
/// The outcome of one case: `pass`, `parse` for a bundle or root that does
/// not parse, or the case name of the rejection.
fn run_case(name : String) -> String {
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
  try {
    let root = match case_file(name, "trusted_root.json") {
      Some(text) => @sigstore.TrustedRoot::parse(text)
      None => @sigstore.TrustedRoot::public_good()
    }
    let bundle = @sigstore.Bundle::parse(
      case_file(name, "bundle.sigstore.json").unwrap(),
    )
    let policy = @sigstore.Policy::subject_name(
      @sigstore.SubjectName::parse(identity),
      issuer=@sigstore.Issuer::parse(issuer),
    )
    outcome(
      @sigstore.verify(
        bundle,
        @sigstore.ArtifactDigest::of_bytes(@utf8.encode(artifact)),
        root,
        policy,
        now=later,
      ),
    )
  } catch {
    _ => "parse"
  }
}

///|
/// A short name for a verdict: `pass`, or the rejection case.
fn outcome(verdict : @sigstore.Verdict) -> String {
  match verdict {
    Verified(_) => "pass"
    Rejected(Unsupported(feature)) =>
      match feature {
        PublicKeyMaterial => "unsupported public key"
        TimestampAlgorithm(_) => "unsupported timestamp algorithm"
        RekorV2 => "unsupported Rekor v2"
        EntryKind(..) => "unsupported entry kind"
        KeyType(_) => "unsupported key type"
        DigestAlgorithm(_) => "unsupported digest"
      }
    Rejected(Invalid(failure)) =>
      match failure {
        BundleShape(_) => "bundle shape"
        TransparencyLog(_) => "transparency log"
        TransparencyLogTime(..) => "transparency log time"
        TransparencyLogBody(_) => "transparency log body"
        InclusionProof(_) => "inclusion proof"
        Checkpoint(_) => "checkpoint"
        Certificate(_) => "certificate"
        CertificateValidity(..) => "certificate validity"
        CertificateChain(_) => "certificate chain"
        CertificateTimestamp(_) => "certificate timestamp"
        PayloadType(_) => "payload type"
        ContentSignature => "content signature"
        Statement(_) => "statement"
        Timestamp(_) => "timestamp"
        TimestampAuthority(_) => "timestamp authority"
        TimestampTime(..) => "timestamp time"
        ArtifactDigestMismatch(_) => "artifact digest"
        Policy(_) => "policy"
      }
  }
}

///|
/// The expected outcome of each sigstore-conformance case at `acb38c9`. Cases
/// that end in `_fail` must not pass. Rekor v2, Rekor v1 `intoto/0.0.2`,
/// managed-key and timestamp authority cases are out of scope (design SCOPE-1) and must give a
/// not-supported reason or fail to parse.
let expected_outcomes : Array[(String, String)] = [
  ("bundle-empty-certificate-chain_fail", "parse"),
  ("bundle-from-wrong-instance_fail", "transparency log"),
  ("bundle-invalid-base64-signature_fail", "parse"),
  ("bundle-malformed-json_fail", "parse"),
  ("bundle-negative-log-index_fail", "parse"),
  ("bundle-unknown-version_fail", "parse"),
  ("bundle-with-root-cert_fail", "parse"),
  ("bundle-with-sct-with-extensions", "unsupported Rekor v2"),
  ("checkpoint-bad-keyhint_fail", "checkpoint"),
  ("checkpoint-wrong-roothash_fail", "checkpoint"),
  ("dsse-invalid-sig_fail", "transparency log body"),
  ("dsse-mismatch-envelope_fail", "transparency log body"),
  ("dsse-mismatch-sig_fail", "transparency log body"),
  ("happy-path-intoto-in-dsse-v3", "pass"),
  ("happy-path-v0.1", "pass"),
  ("happy-path-v0.2", "pass"),
  ("happy-path-v0.3-new-mediaType", "pass"),
  ("happy-path-v0.3", "pass"),
  ("inclusion-proof-corrupted-hash_fail", "inclusion proof"),
  ("incorrect-public-key_fail", "transparency log"),
  ("integrated-time-in-future_fail", "certificate validity"),
  ("intoto-expired-certificate_fail", "unsupported entry kind"),
  ("intoto-log-entry-mismatch_fail", "unsupported entry kind"),
  ("intoto-missing-inclusion-proof_fail", "parse"),
  ("intoto-set-outside-signing-cert-validity_fail", "unsupported entry kind"),
  ("intoto-tsa-timestamp-outside-cert-validity_fail", "unsupported entry kind"),
  ("intoto-with-custom-trust-root", "unsupported entry kind"),
  ("invalid-checkpoint-signature_fail", "checkpoint"),
  ("invalid-ct-key_fail", "certificate timestamp"),
  ("invalid-inclusion-proof_fail", "parse"),
  ("managed-key-and-trusted-root", "unsupported public key"),
  ("managed-key-happy-path", "unsupported public key"),
  ("managed-key-no-key_fail", "unsupported public key"),
  ("managed-key-wrong-key_fail", "unsupported public key"),
  ("message-digest-mismatch_fail", "transparency log body"),
  ("rekor2-checkpoint-cosigned", "unsupported Rekor v2"),
  ("rekor2-checkpoint-missing-log-signature_fail", "unsupported Rekor v2"),
  ("rekor2-checkpoint-missing-origin_fail", "unsupported Rekor v2"),
  ("rekor2-checkpoint-missing-root-hash_fail", "unsupported Rekor v2"),
  ("rekor2-checkpoint-missing-size_fail", "unsupported Rekor v2"),
  ("rekor2-checkpoint-multiple-cosigs", "unsupported Rekor v2"),
  ("rekor2-checkpoint-no-matching-signature_fail", "unsupported Rekor v2"),
  ("rekor2-checkpoint-origin-not-first", "unsupported Rekor v2"),
  ("rekor2-checkpoint-two-sigs-cosigned", "unsupported Rekor v2"),
  ("rekor2-checkpoint-two-sigs-from-origin", "unsupported Rekor v2"),
  ("rekor2-dsse-happy-path", "unsupported Rekor v2"),
  ("rekor2-dsse-invalid-sig_fail", "unsupported Rekor v2"),
  ("rekor2-dsse-mismatch-envelope_fail", "unsupported Rekor v2"),
  ("rekor2-dsse-mismatch-sig_fail", "unsupported Rekor v2"),
  ("rekor2-happy-path", "unsupported Rekor v2"),
  ("rekor2-no-inclusion-proof_fail", "parse"),
  ("rekor2-no-timestamp_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-outside-trust-root-tsa-validity_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-outside-tsa-cert-validity_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-payload-mismatch_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-untrusted-tsa-with-embedded-cert_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-untrusted-tsa-without-embedded-cert_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-with-embedded-cert", "unsupported Rekor v2"),
  ("rekor2-timestamp-with-expired-cert-chain", "unsupported Rekor v2"),
  ("rekor2-timestamp-with-incorrect-time_fail", "unsupported Rekor v2"),
  ("rekor2-timestamp-without-embedded-cert", "unsupported Rekor v2"),
  ("set-invalid-signature_fail", "transparency log"),
  ("signature-mismatch_fail", "transparency log body"),
  ("trust-root-tlog-missing-validity-start_fail", "parse"),
  ("trust-root-tlog-validity-end-inclusive", "pass"),
  ("trust-root-tsa-validity-end-inclusive", "unsupported Rekor v2"),
  ("wrong-hashedrekord-artifact_fail", "transparency log body"),
  ("wrong-hashedrekord-cert-and-sig_fail", "transparency log body"),
  ("wrong-hashedrekord-entry_fail", "transparency log body"),
  ("wrong-material_fail", "artifact digest"),
]

///|
test "every conformance case gives its expected outcome" {
  let names = conformance_cases()
  assert_eq(names.length(), 70)
  assert_eq(names.length(), expected_outcomes.length())
  for name in names {
    guard expected_outcomes.search_by(entry => entry.0 == name) is Some(index) else {
      fail("no expected outcome for \{name}")
    }
    let expected = expected_outcomes[index].1
    assert_eq(run_case(name), expected, msg=name)
    if name.has_suffix("_fail") {
      assert_true(expected != "pass", msg=name)
    } else {
      assert_true(expected == "pass" || expected.has_prefix("unsupported"), msg=name)
    }
  }
}
