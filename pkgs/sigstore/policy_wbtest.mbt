///|
/// The claims of the finos/morphir-rust provider-snapshot/v0.2.0 certificate
/// that the policies read.
let rust_claims : CertificateClaims = {
  issuer: Some("https://token.actions.githubusercontent.com"),
  subject_names: [
    "https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/tags/provider-snapshot/v0.2.0",
  ],
  build_signer_uri: None,
  build_signer_digest: None,
  runner_environment: Some("github-hosted"),
  source_repository_uri: Some("https://github.com/finos/morphir-rust"),
  source_repository_digest: None,
  source_repository_ref: Some("refs/tags/provider-snapshot/v0.2.0"),
  source_repository_identifier: Some("513894754"),
  source_repository_owner_uri: Some("https://github.com/finos"),
  source_repository_owner_identifier: Some("35377814"),
  build_config_uri: None,
  build_config_digest: None,
  build_trigger: None,
  run_invocation_uri: None,
  source_repository_visibility: None,
}

///|
fn rust_workflow(git_ref? : GitRef) -> Policy raise {
  Policy::signer_workflow(
    GitHubRepository::parse("finos/morphir-rust"),
    WorkflowPath::parse(".github/workflows/release-provider-snapshot.yml"),
    git_ref?,
  )
}

///|
fn release_policy() -> Policy raise {
  Policy::signer_workflow(
    GitHubRepository::parse("finos/morphir-rust"),
    WorkflowPath::parse(".github/workflows/release.yml"),
  )
}

///|
fn with_san(san : String) -> CertificateClaims {
  { ..rust_claims, subject_names: [san] }
}

///|
test "the claims of the real certificate are the claims of these tests" {
  let case_bundle = "morphir-rust-provider-snapshot-0.2.0.sigstore.json"
  let text = match @fixtures.github.iter().find_first(file => file.0 == case_bundle) {
    Some(file) => file.1
    None => fail("no \{case_bundle}")
  }
  let verdict = verify(
    Bundle::parse(text),
    ArtifactDigest::parse(
      "sha256:03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd",
    ),
    TrustedRoot::public_good(),
    rust_workflow(),
    now=Instant::from_unix_seconds(1793000000L),
  )
  guard verdict is Verified(facts) else { fail("rejected") }
  let claims = facts.claims
  assert_eq(claims.issuer, rust_claims.issuer)
  assert_eq(claims.subject_names, rust_claims.subject_names)
  assert_eq(claims.runner_environment, rust_claims.runner_environment)
  assert_eq(claims.source_repository_uri, rust_claims.source_repository_uri)
  assert_eq(claims.source_repository_ref, rust_claims.source_repository_ref)
  assert_eq(claims.source_repository_identifier, rust_claims.source_repository_identifier)
  assert_eq(claims.source_repository_owner_uri, rust_claims.source_repository_owner_uri)
  assert_eq(
    claims.source_repository_owner_identifier,
    rust_claims.source_repository_owner_identifier,
  )
  assert_eq(rust_workflow().check_claims(claims), None)
}

///|
test "scenario: other issuer" {
  let google = { ..rust_claims, issuer: Some("https://accounts.google.com") }
  let mismatch = rust_workflow().check_claims(google)
  assert_eq(
    mismatch,
    Some(
      IssuerMismatch(
        expected="https://token.actions.githubusercontent.com",
        actual=Some("https://accounts.google.com"),
      ),
    ),
  )
  assert_eq(
    mismatch.unwrap().message(),
    "the issuer is \"https://accounts.google.com\", not \"https://token.actions.githubusercontent.com\"",
  )
  // A certificate without an issuer claim.
  assert_eq(
    rust_workflow().check_claims({ ..rust_claims, issuer: None }),
    Some(IssuerMismatch(expected="https://token.actions.githubusercontent.com", actual=None)),
  )
  // A policy for the other issuer matches it.
  let policy = Policy::signer_workflow(
    GitHubRepository::parse("finos/morphir-rust"),
    WorkflowPath::parse(".github/workflows/release-provider-snapshot.yml"),
    issuer=Issuer::parse("https://accounts.google.com"),
  )
  assert_eq(policy.check_claims(google), None)
}

///|
test "scenario: path prefix is not a match" {
  let evil = with_san(
    "https://github.com/finos/morphir-rust/.github/workflows/release.yml.evil.yml@refs/heads/main",
  )
  assert_eq(
    release_policy().check_claims(evil),
    Some(
      IdentityMismatch(
        expected="https://github.com/finos/morphir-rust/.github/workflows/release.yml@*",
        actual=evil.subject_names,
      ),
    ),
  )
  // The same workflow at a ref matches.
  let good = with_san(
    "https://github.com/finos/morphir-rust/.github/workflows/release.yml@refs/heads/main",
  )
  assert_eq(release_policy().check_claims(good), None)
}

///|
test "a signer workflow matches the whole SAN form" {
  let base = "https://github.com/finos/morphir-rust/.github/workflows/release.yml"
  let refused = [
    // No ref, or a ref without refs/.
    base + "@", base + "@main", base,
    // A repository whose name starts with the policy repository.
    "https://github.com/finos/morphir-rust-evil/.github/workflows/release.yml@refs/heads/main",
    // Another owner, host or scheme.
    "https://github.com/finos2/morphir-rust/.github/workflows/release.yml@refs/heads/main",
    "https://example.com/finos/morphir-rust/.github/workflows/release.yml@refs/heads/main",
    "http://github.com/finos/morphir-rust/.github/workflows/release.yml@refs/heads/main",
    // The workflow in a subfolder.
    "https://github.com/finos/morphir-rust/.github/workflows/x/release.yml@refs/heads/main",
  ]
  for san in refused {
    assert_true(release_policy().check_claims(with_san(san)) is Some(IdentityMismatch(..)), msg=san)
  }
  // Owner and repository ignore case; path and ref do not.
  assert_eq(
    release_policy().check_claims(
      with_san("https://github.com/FINOS/Morphir-Rust/.github/workflows/release.yml@refs/heads/main"),
    ),
    None,
  )
  assert_true(
    release_policy().check_claims(
      with_san("https://github.com/finos/morphir-rust/.github/workflows/Release.yml@refs/heads/main"),
    )
    is Some(IdentityMismatch(..)),
  )
  let pinned = Policy::signer_workflow(
    GitHubRepository::parse("finos/morphir-rust"),
    WorkflowPath::parse(".github/workflows/release.yml"),
    git_ref=GitRef::parse("refs/heads/main"),
  )
  assert_eq(pinned.check_claims(with_san(base + "@refs/heads/main")), None)
  assert_true(pinned.check_claims(with_san(base + "@refs/heads/Main")) is Some(IdentityMismatch(..)))
  assert_true(
    pinned.check_claims(with_san(base + "@refs/heads/main2")) is Some(IdentityMismatch(..)),
  )
  // One of several SANs is enough.
  let two = { ..rust_claims, subject_names: ["mailto:a@example.com", base + "@refs/heads/main"] }
  assert_eq(pinned.check_claims(two), None)
}

///|
test "scenario: source repository" {
  let policy = rust_workflow().source_repository(GitHubRepository::parse("finos/morphir-rust"))
  assert_eq(policy.check_claims(rust_claims), None)
  assert_eq(
    policy.check_claims({
      ..rust_claims,
      source_repository_uri: Some("https://github.com/FINOS/Morphir-Rust"),
    }),
    None,
  )
  assert_eq(
    policy.check_claims({ ..rust_claims, source_repository_uri: None }),
    Some(
      ClaimMismatch(
        claim=SourceRepository,
        expected="https://github.com/finos/morphir-rust",
        actual=None,
      ),
    ),
  )
}

///|
test "scenario: recreated repository" {
  let policy = rust_workflow().repository_id(GitHubId::parse("513894754"))
  assert_eq(policy.check_claims(rust_claims), None)
  let recreated = { ..rust_claims, source_repository_identifier: Some("999") }
  let mismatch = policy.check_claims(recreated)
  assert_eq(
    mismatch,
    Some(ClaimMismatch(claim=RepositoryId, expected="513894754", actual=Some("999"))),
  )
  assert_eq(mismatch.unwrap().message(), "the repository ID is \"999\", not \"513894754\"")
  // A missing extension fails a required claim.
  assert_eq(
    policy.check_claims({ ..rust_claims, source_repository_identifier: None }),
    Some(ClaimMismatch(claim=RepositoryId, expected="513894754", actual=None)),
  )
}

///|
test "owner and owner ID claims" {
  let owner = rust_workflow().source_owner(GitHubOwner::parse("FINOS"))
  assert_eq(owner.check_claims(rust_claims), None)
  assert_eq(
    owner.check_claims({ ..rust_claims, source_repository_owner_uri: Some("https://github.com/cli") }),
    Some(
      ClaimMismatch(
        claim=SourceOwner,
        expected="https://github.com/FINOS",
        actual=Some("https://github.com/cli"),
      ),
    ),
  )
  let owner_id = rust_workflow().owner_id(GitHubId::parse("35377814"))
  assert_eq(owner_id.check_claims(rust_claims), None)
  assert_eq(
    owner_id.check_claims({ ..rust_claims, source_repository_owner_identifier: None }),
    Some(ClaimMismatch(claim=OwnerId, expected="35377814", actual=None)),
  )
}

///|
test "scenario: source ref" {
  let policy = rust_workflow().source_ref(GitRef::parse("refs/heads/main"))
  assert_eq(
    policy.check_claims(rust_claims),
    Some(
      ClaimMismatch(
        claim=SourceRef,
        expected="refs/heads/main",
        actual=Some("refs/tags/provider-snapshot/v0.2.0"),
      ),
    ),
  )
  let tag = rust_workflow().source_ref(GitRef::parse("refs/tags/provider-snapshot/v0.2.0"))
  assert_eq(tag.check_claims(rust_claims), None)
}

///|
test "scenario: self-hosted runner" {
  let policy = rust_workflow().hosted_runners_only()
  let self_hosted = { ..rust_claims, runner_environment: Some("self-hosted") }
  let mismatch = policy.check_claims(self_hosted)
  assert_eq(mismatch, Some(RunnerEnvironment(actual=Some("self-hosted"))))
  assert_eq(
    mismatch.unwrap().message(),
    "the runner environment is \"self-hosted\", not \"github-hosted\"",
  )
  // No runner environment extension fails too.
  assert_eq(
    policy.check_claims({ ..rust_claims, runner_environment: None }),
    Some(RunnerEnvironment(actual=None)),
  )
  // Without the requirement, a self-hosted runner matches.
  assert_eq(rust_workflow().check_claims(self_hosted), None)
}

///|
test "scenario: GitHub-hosted runner" {
  assert_eq(rust_workflow().hosted_runners_only().check_claims(rust_claims), None)
  let policy = Policy::github_workflow(
    GitHubRepository::parse("finos/morphir-rust"),
    workflow=WorkflowPath::parse(".github/workflows/release-provider-snapshot.yml"),
  )
  assert_eq(policy.check_claims(rust_claims), None)
  assert_true(
    policy.check_claims({ ..rust_claims, runner_environment: Some("self-hosted") })
    is Some(RunnerEnvironment(..)),
  )
}

///|
test "a policy reports the first claim that does not match" {
  let policy = rust_workflow()
    .repository_id(GitHubId::parse("1"))
    .source_ref(GitRef::parse("refs/heads/main"))
    .hosted_runners_only()
  assert_true(policy.check_claims(rust_claims) is Some(ClaimMismatch(claim=RepositoryId, ..)))
  assert_true(
    policy.check_claims({ ..rust_claims, issuer: None, runner_environment: None })
    is Some(IssuerMismatch(..)),
  )
}

///|
test "a mismatch message names both values" {
  assert_eq(
    IdentityMismatch(expected="https://a@*", actual=["https://b", "https://c"]).message(),
    "the certificate identity \"https://b\", \"https://c\" does not match \"https://a@*\"",
  )
  assert_eq(
    ClaimMismatch(claim=SourceOwner, expected="https://github.com/a", actual=None).message(),
    "the source repository owner is nothing, not \"https://github.com/a\"",
  )
  assert_eq(
    RunnerEnvironment(actual=None).message(),
    "the runner environment is nothing, not \"github-hosted\"",
  )
}

///|
/// The mismatch of `claims` with a statement of SLSA provenance v1, the
/// predicate type that `Policy::github_workflow` requires by default.
fn Policy::check_claims(self : Policy, claims : CertificateClaims) -> PolicyMismatch? {
  self.mismatch(claims, Some(statement_of("https://slsa.dev/provenance/v1")))
}

///|
fn statement_of(predicate_type : String) -> Statement {
  let parsed = PredicateType::parse(predicate_type) catch {
    _ => abort("bad predicate type \{predicate_type}")
  }
  { predicate_type: parsed, subjects: [], payload: b"" }
}

///|
test "a GitHub workflow policy requires SLSA provenance by default" {
  let claims = rust_claims
  let policy = Policy::github_workflow(
    GitHubRepository::parse("finos/morphir-rust"),
    workflow=WorkflowPath::parse(".github/workflows/release-provider-snapshot.yml"),
  )
  assert_eq(policy.mismatch(claims, Some(statement_of("https://slsa.dev/provenance/v1"))), None)
  assert_eq(
    policy.mismatch(claims, Some(statement_of("https://spdx.dev/Document/v2.3"))),
    Some(
      PredicateTypeMismatch(
        expected=PredicateType::slsa_provenance_v1(),
        actual=Some(statement_of("https://spdx.dev/Document/v2.3").predicate_type),
      ),
    ),
  )
  // A message-signature bundle has no statement.
  assert_eq(
    policy.mismatch(claims, None),
    Some(PredicateTypeMismatch(expected=PredicateType::slsa_provenance_v1(), actual=None)),
  )
}

///|
test "a policy can require another predicate type, or none" {
  let claims = rust_claims
  let sbom = PredicateType::parse("https://spdx.dev/Document/v2.3") catch {
    _ => fail("parse")
  }
  let repository = GitHubRepository::parse("finos/morphir-rust") catch {
    _ => fail("parse")
  }
  let workflow = WorkflowPath::parse(".github/workflows/release-provider-snapshot.yml") catch {
    _ => fail("parse")
  }
  let sbom_policy = Policy::github_workflow(repository, workflow~, predicate_type=sbom)
  assert_eq(sbom_policy.mismatch(claims, Some(statement_of("https://spdx.dev/Document/v2.3"))), None)
  // Policy::signer_workflow alone does not require a predicate type.
  assert_eq(Policy::signer_workflow(repository, workflow).mismatch(claims, None), None)
}
