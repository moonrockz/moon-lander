///|
/// One case of `testdata/github/timestamp-cases.json`.
struct TimestampCase {
  bundle : String
  kind : String
  digest : String
  repository : String
  repository_id : String
  owner_id : String
  tag : String?
  workflow : String?
  predicate_type : String
}

///|
fn timestamp_cases() -> Array[TimestampCase] raise {
  guard @json.parse(fixture(@fixtures.github, "timestamp-cases.json")) is Array(items) else {
    fail("timestamp-cases.json is not an array")
  }
  items.map(item => {
    guard item is Object(map) else { fail("a case is not an object") }
    fn optional(name : String) -> String? {
      match map.get(name) {
        Some(String(value)) => Some(value)
        _ => None
      }
    }

    fn text(name : String) -> String raise {
      guard optional(name) is Some(value) else { fail("no \{name}") }
      value
    }

    {
      bundle: text("bundle"),
      kind: text("kind"),
      digest: text("digest"),
      repository: text("repository"),
      repository_id: text("repositoryId"),
      owner_id: text("ownerId"),
      tag: optional("tag"),
      workflow: optional("workflow"),
      predicate_type: text("predicateType"),
    }
  })
}

///|
fn timestamp_case(kind : String) -> TimestampCase raise {
  guard timestamp_cases().iter().find_first(case => case.kind == kind) is Some(case) else {
    fail("no \{kind} case")
  }
  case
}

///|
/// The private-repository provenance case and its workflow policy.
fn private_case() -> (TimestampCase, @sigstore.Policy) raise {
  let case = timestamp_case("workflow")
  let policy = @sigstore.Policy::github_workflow(
    @sigstore.GitHubRepository::parse(case.repository),
    workflow=@sigstore.WorkflowPath::parse(case.workflow.unwrap()),
  )
  (case, policy)
}

///|
fn verify_timestamp_document(
  case : TimestampCase,
  doc : Json,
  policy : @sigstore.Policy,
  root? : @sigstore.TrustedRoot = @sigstore.TrustedRoot::github(),
  now? : @sigstore.Instant = later,
) -> @sigstore.Verdict raise {
  @sigstore.verify(
    @sigstore.Bundle::parse(doc.stringify()),
    @sigstore.ArtifactDigest::parse(case.digest),
    root,
    policy,
    now~,
  )
}

///|
/// A time after the cli/cli v2.103.3 release timestamp (2026-10-26T19:20:09Z).
let after_release : @sigstore.Instant = @sigstore.Instant::from_unix_seconds(1794000000L)

///|
fn timestamp_document(case : TimestampCase) -> Json raise {
  @json.parse(fixture(@fixtures.github, case.bundle))
}

///|
test "scenario: private repository provenance verifies with its timestamp" {
  let (case, policy) = private_case()
  for root in [@sigstore.TrustedRoot::github(), @sigstore.TrustedRoot::github_attestations()] {
    let verdict = verify_timestamp_document(case, timestamp_document(case), policy, root~)
    guard verdict is Verified(facts) else { fail(outcome(verdict)) }
    guard facts.times is [{ source: Authority(uri~), time }] else {
      fail("not one timestamp time")
    }
    assert_eq(uri, "timestamp.githubapp.com")
    assert_true(time.unix_seconds() > 1713800000L && time.unix_seconds() < 1713810000L)
    assert_eq(facts.claims.source_repository_identifier, Some(case.repository_id))
    assert_eq(facts.claims.runner_environment, Some("github-hosted"))
  }
}

///|
/// The release policy of a release case.
fn release_policy(case : TimestampCase) -> @sigstore.Policy raise {
  @sigstore.Policy::github_release(
    @sigstore.GitHubRepository::parse(case.repository),
    tag=@sigstore.ReleaseTag::parse(case.tag.unwrap()),
    predicate_type=@sigstore.PredicateType::parse(case.predicate_type),
  )
}

///|
test "scenario: release asset" {
  for case in timestamp_cases() {
    guard case.kind == "release" else { continue }
    let policy = release_policy(case)
      .repository_id(@sigstore.GitHubId::parse(case.repository_id))
      .owner_id(@sigstore.GitHubId::parse(case.owner_id))
    for root in [@sigstore.TrustedRoot::github(), @sigstore.TrustedRoot::github_attestations()] {
      let verdict = verify_timestamp_document(case, timestamp_document(case), policy, root~, now=after_release)
      guard verdict is Verified(facts) else { fail("\{case.bundle}: \{outcome(verdict)}") }
      assert_true(facts.times is [{ source: Authority(..), .. }])
      assert_eq(facts.claims.issuer, None)
      assert_eq(facts.claims.subject_names, ["https://dotcom.releases.github.com"])
      guard facts.statement is Some(statement) else { fail("no statement") }
      assert_eq(statement.predicate_type.to_string(), case.predicate_type)
    }
  }
}

///|
test "scenario: release certificate without issuer" {
  let case = timestamp_case("release")
  let verdict = verify_timestamp_document(case, timestamp_document(case), release_policy(case), now=after_release)
  assert_true(verdict is Verified(_))
}

///|
test "release policies refuse each wrong field" {
  let case = timestamp_case("release")
  fn release_reason(policy : @sigstore.Policy) -> @sigstore.PolicyMismatch? raise {
    let verdict = verify_timestamp_document(case, timestamp_document(case), policy, now=after_release)
    guard verdict is Rejected(Invalid(Policy([reason]))) else { return None }
    Some(reason)
  }

  let repository = @sigstore.GitHubRepository::parse("cli/cli")
  // Other tag.
  let other_tag = @sigstore.Policy::github_release(repository, tag=@sigstore.ReleaseTag::parse("v2.103.2"))
  guard release_reason(other_tag) is Some(ReleaseMismatch(field=Tag, expected~, actual~)) else {
    fail("expected a tag mismatch")
  }
  assert_eq(expected, "v2.103.2")
  assert_eq(actual, Some("v2.103.3"))
  // Other repository ID.
  let other_id = release_policy(case).repository_id(@sigstore.GitHubId::parse("1"))
  guard release_reason(other_id) is Some(ReleaseMismatch(field=RepositoryId, actual~, ..)) else {
    fail("expected a repository ID mismatch")
  }
  assert_eq(actual, Some("212613049"))
  // Other owner ID.
  let other_owner = release_policy(case).owner_id(@sigstore.GitHubId::parse("2"))
  assert_true(release_reason(other_owner) is Some(ReleaseMismatch(field=OwnerId, ..)))
  // Other repository; the name is case-insensitive.
  let other_repository = @sigstore.Policy::github_release(
    @sigstore.GitHubRepository::parse("cli/go-gh"),
    tag=@sigstore.ReleaseTag::parse("v2.103.3"),
  )
  assert_true(release_reason(other_repository) is Some(ReleaseMismatch(field=Repository, ..)))
  let upper = @sigstore.Policy::github_release(
    @sigstore.GitHubRepository::parse("CLI/Cli"),
    tag=@sigstore.ReleaseTag::parse("v2.103.3"),
  )
  assert_eq(release_reason(upper), None)
  // The v0.1 predicate type does not pass the default v0.2 policy.
  let old = timestamp_cases().filter(case => case.predicate_type.has_suffix("/v0.1"))[0]
  let default_type = @sigstore.Policy::github_release(
    @sigstore.GitHubRepository::parse(old.repository),
    tag=@sigstore.ReleaseTag::parse(old.tag.unwrap()),
  )
  let verdict = verify_timestamp_document(old, timestamp_document(old), default_type, now=after_release)
  assert_true(verdict is Rejected(Invalid(Policy([PredicateTypeMismatch(..)]))))
  // A workflow policy does not accept a release certificate.
  let (_, workflow) = private_case()
  assert_true(release_reason(workflow) is Some(IssuerMismatch(actual=None, ..)))
}

///|
test "release predicate fields are read from the statement" {
  let case = timestamp_case("release")
  let doc = timestamp_document(case)
  guard find(doc, "dsseEnvelope") is Object(envelope) &&
    envelope.get("payload") is Some(String(payload)) else {
    fail("no payload")
  }
  let statement = @json.parse(@utf8.decode(@encoding.decode_base64(payload)))
  // The purl must name the same repository and the exact tag.
  assert_eq(find(statement, "predicate.purl"), Json::string("pkg:github/cli/cli@v2.103.3"))
  // The tag commit subject has a uri and a SHA-1 digest, and no name.
  assert_true(find(statement, "subject.0.uri") is String(_))
}

///|
test "scenario: untrusted timestamp authority" {
  let (case, policy) = private_case()
  let verdict = verify_timestamp_document(
    case,
    timestamp_document(case),
    policy,
    root=@sigstore.TrustedRoot::public_good(),
  )
  guard verdict is Rejected(Invalid(TimestampAuthority(_))) else { fail(outcome(verdict)) }
}

///|
test "scenario: timestamp time outside the authority validity" {
  let (case, policy) = private_case()
  let doc = @json.parse(@sigstore.github_trusted_root_json())
  for authority in array_at(doc, "timestampAuthorities") {
    set_field(authority, "validFor", "end", Json::string("2024-01-01T00:00:00Z"))
  }
  let root = @sigstore.TrustedRoot::parse(doc.stringify())
  let verdict = verify_timestamp_document(case, timestamp_document(case), policy, root~)
  guard verdict is Rejected(Invalid(TimestampAuthority(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the timestamp time is outside the validity of the authority")
}

///|
test "scenario: timestamp for another signature" {
  let (case, policy) = private_case()
  let doc = timestamp_document(case)
  let signature = find(doc, "dsseEnvelope.signatures.0")
  guard find(signature, "sig") is String(sig) else { fail("no signature") }
  set_field(signature, "", "sig", Json::string(flip_base64(sig, 10)))
  let verdict = verify_timestamp_document(case, doc, policy)
  guard verdict is Rejected(Invalid(Timestamp(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the message imprint is not the hash of the bundle signature")
}

///|
test "scenario: timestamp in the future" {
  let (case, policy) = private_case()
  let now = @sigstore.Instant::from_unix_seconds(1713700000L)
  let verdict = verify_timestamp_document(case, timestamp_document(case), policy, now~)
  guard verdict is Rejected(Invalid(TimestampTime(..))) else { fail(outcome(verdict)) }
}

///|
test "scenario: a changed timestamp does not verify" {
  let (case, policy) = private_case()
  let doc = timestamp_document(case)
  let token = find(doc, "verificationMaterial.timestampVerificationData.rfc3161Timestamps.0")
  guard find(token, "signedTimestamp") is String(text) else { fail("no timestamp") }
  let bytes = @encoding.decode_base64(text)
  // The last byte is in the SignerInfo signature.
  set_field(token, "", "signedTimestamp", Json::string(flip_base64(text, bytes.length() - 1)))
  let verdict = verify_timestamp_document(case, doc, policy)
  guard verdict is Rejected(Invalid(TimestampAuthority(reason))) else { fail(outcome(verdict)) }
  assert_eq(reason, "the timestamp signature does not verify")
}

///|
test "scenario: GitHub attestations root keeps the public-good SCT rule" {
  // Public-good bundles verify with the combined root.
  for case in github_cases() {
    let verdict = verify_case(case, case_policy(case), root=@sigstore.TrustedRoot::github_attestations())
    assert_true(verdict is Verified(_), msg=case.bundle)
  }
  // A combined root whose public-good part lists only another CT log still
  // requires the public-good leaf's SCT.
  let public = changed_root(doc => {
    let logs = array_at(doc, "ctlogs")
    let first = logs[0]
    logs.clear()
    logs.push(first)
  })
  let combined = @sigstore.TrustedRoot::combine([public, @sigstore.TrustedRoot::github()])
  let verdict = verify_morphir(morphir_policy(), root=combined)
  guard verdict is Rejected(Invalid(CertificateTimestamp(_))) else { fail(outcome(verdict)) }
}

///|
test "scenario: a public-good leaf with only a timestamp needs a log entry" {
  // The conformance in-toto bundle has a Rekor v1 entry and a timestamp, and its
  // root lists a transparency log. Without the entry, the timestamp alone does
  // not pass.
  let name = "intoto-with-custom-trust-root"
  let doc = conformance_document(name)
  array_at(doc, "verificationMaterial.tlogEntries").clear()
  assert_eq(verify_conformance_document(name, doc), "transparency log")
}

///|
test "the SCT rule does not depend on the order of combined roots" {
  // A root with the public-good CAs and no CT logs, and a root with the
  // public-good CAs and only another CT log: the leaf's SCT is still required.
  let lax = changed_root(doc => array_at(doc, "ctlogs").clear())
  let other_log = changed_root(doc => {
    let logs = array_at(doc, "ctlogs")
    let first = logs[0]
    logs.clear()
    logs.push(first)
  })
  for roots in [[lax, other_log], [other_log, lax]] {
    let verdict = verify_morphir(morphir_policy(), root=@sigstore.TrustedRoot::combine(roots))
    guard verdict is Rejected(Invalid(CertificateTimestamp(_))) else { fail(outcome(verdict)) }
  }
}

///|
test "scenario: workflow claim on a release policy" {
  let case = timestamp_case("release")
  let policy = release_policy(case).source_ref(@sigstore.GitRef::parse("refs/heads/main"))
  let verdict = verify_timestamp_document(case, timestamp_document(case), policy, now=after_release)
  guard verdict is Rejected(Invalid(Policy([ClaimMismatch(claim=SourceRef, actual=None, ..)]))) else {
    fail(outcome(verdict))
  }
}

///|
test "a log listed by two combined roots counts for both" {
  // A root with the public-good logs and no CAs, combined with the full
  // public-good root, in either order: the entry comes from a log of the root
  // that issued the leaf too.
  let logs_only = changed_root(doc => array_at(doc, "certificateAuthorities").clear())
  for roots in [[logs_only, @sigstore.TrustedRoot::public_good()], [@sigstore.TrustedRoot::public_good(), logs_only]] {
    let verdict = verify_morphir(morphir_policy(), root=@sigstore.TrustedRoot::combine(roots))
    assert_true(verdict is Verified(_), msg=outcome(verdict))
  }
}
