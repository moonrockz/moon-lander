///|
let morphir_san : String = "https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/tags/provider-snapshot/v0.2.0"

///|
let morphir_workflow : String = ".github/workflows/release-provider-snapshot.yml"

///|
fn repository(text : String) -> @sigstore.GitHubRepository raise {
  @sigstore.GitHubRepository::parse(text)
}

///|
fn workflow(text : String) -> @sigstore.WorkflowPath raise {
  @sigstore.WorkflowPath::parse(text)
}

///|
fn git_ref(text : String) -> @sigstore.GitRef raise {
  @sigstore.GitRef::parse(text)
}

///|
fn id(text : String) -> @sigstore.GitHubId raise {
  @sigstore.GitHubId::parse(text)
}

///|
/// The signer workflow policy of morphir-rust, at any ref.
fn rust_signer() -> @sigstore.Policy raise {
  @sigstore.Policy::signer_workflow(repository("finos/morphir-rust"), workflow(morphir_workflow))
}

///|
/// The policy mismatches of a rejected verdict.
fn mismatches(verdict : @sigstore.Verdict) -> Array[@sigstore.PolicyMismatch] raise {
  guard verdict is Rejected(Invalid(Policy(reasons))) else { fail(outcome(verdict)) }
  reasons
}

///|
/// The single mismatch of a verdict for one policy, as its message.
fn mismatch_message(verdict : @sigstore.Verdict) -> String raise {
  let reasons = mismatches(verdict)
  assert_eq(reasons.length(), 1)
  reasons[0].message()
}

///|
test "scenario: signer workflow without ref" {
  let verdict = verify_morphir(rust_signer())
  guard verdict is Verified(facts) else { fail(outcome(verdict)) }
  assert_eq(facts.claims.subject_names, [morphir_san])
  // With the ref of the SAN.
  let at_ref = @sigstore.Policy::signer_workflow(
    repository("finos/morphir-rust"),
    workflow(morphir_workflow),
    git_ref=git_ref("refs/tags/provider-snapshot/v0.2.0"),
  )
  assert_eq(outcome(verify_morphir(at_ref)), "pass")
}

///|
test "a signer workflow at another ref does not match" {
  let other = @sigstore.Policy::signer_workflow(
    repository("finos/morphir-rust"),
    workflow(morphir_workflow),
    git_ref=git_ref("refs/heads/main"),
  )
  let reasons = mismatches(verify_morphir(other))
  guard reasons is [IdentityMismatch(expected~, actual~)] else { fail("\{reasons.length()}") }
  assert_eq(
    expected, "https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/heads/main",
  )
  assert_eq(actual, [morphir_san])
}

///|
test "scenario: other workflow file" {
  let policy = @sigstore.Policy::signer_workflow(
    repository("finos/morphir-rust"),
    workflow(".github/workflows/release.yml"),
  )
  let reasons = mismatches(verify_morphir(policy))
  guard reasons is [IdentityMismatch(expected~, actual~)] else { fail("\{reasons.length()}") }
  assert_eq(expected, "https://github.com/finos/morphir-rust/.github/workflows/release.yml@*")
  assert_eq(actual, [morphir_san])
}

///|
test "owner and repository match without case; path and ref match exactly" {
  let upper = @sigstore.Policy::github_workflow(
    repository("FINOS/Morphir-Rust"),
    workflow=workflow(morphir_workflow),
    git_ref=git_ref("refs/tags/provider-snapshot/v0.2.0"),
  ).source_owner(@sigstore.GitHubOwner::parse("FINOS"))
  assert_eq(outcome(verify_morphir(upper)), "pass")
  let path = @sigstore.Policy::signer_workflow(
    repository("finos/morphir-rust"),
    workflow(".github/workflows/Release-Provider-Snapshot.yml"),
  )
  assert_true(mismatches(verify_morphir(path)) is [IdentityMismatch(..)])
  let ref_case = @sigstore.Policy::signer_workflow(
    repository("finos/morphir-rust"),
    workflow(morphir_workflow),
    git_ref=git_ref("refs/tags/Provider-Snapshot/v0.2.0"),
  )
  assert_true(mismatches(verify_morphir(ref_case)) is [IdentityMismatch(..)])
  let ref_source = rust_signer().source_ref(git_ref("refs/tags/Provider-Snapshot/v0.2.0"))
  assert_true(mismatches(verify_morphir(ref_source)) is [ClaimMismatch(claim=SourceRef, ..)])
}

///|
test "an exact subject name matches only the exact SAN" {
  let exact = @sigstore.Policy::subject_name(@sigstore.SubjectName::parse(morphir_san))
  assert_eq(outcome(verify_morphir(exact)), "pass")
  let upper = @sigstore.Policy::subject_name(
    @sigstore.SubjectName::parse(morphir_san.replace(old="finos", new="FINOS")),
  )
  assert_true(mismatches(verify_morphir(upper)) is [IdentityMismatch(..)])
  let prefix = @sigstore.Policy::subject_name(
    @sigstore.SubjectName::parse(morphir_san[:morphir_san.length() - 1].to_owned()),
  )
  assert_true(mismatches(verify_morphir(prefix)) is [IdentityMismatch(..)])
}

///|
test "the policy issuer must equal the certificate issuer" {
  let google = @sigstore.Policy::subject_name(
    @sigstore.SubjectName::parse(morphir_san),
    issuer=@sigstore.Issuer::parse("https://accounts.google.com"),
  )
  let reasons = mismatches(verify_morphir(google))
  guard reasons is [IssuerMismatch(expected~, actual~)] else { fail("\{reasons.length()}") }
  assert_eq(expected, "https://accounts.google.com")
  assert_eq(actual, Some("https://token.actions.githubusercontent.com"))
}

///|
test "scenario: source repository" {
  let policy = rust_signer().source_repository(repository("finos/morphir-rust"))
  assert_eq(outcome(verify_morphir(policy)), "pass")
  let other = rust_signer().source_repository(repository("finos/morphir-ui"))
  let reasons = mismatches(verify_morphir(other))
  guard reasons is [ClaimMismatch(claim=SourceRepository, expected~, actual~)] else {
    fail("\{reasons.length()}")
  }
  assert_eq(expected, "https://github.com/finos/morphir-ui")
  assert_eq(actual, Some("https://github.com/finos/morphir-rust"))
}

///|
test "repository ID, owner ID and owner claims" {
  let all = rust_signer()
    .repository_id(id("513894754"))
    .owner_id(id("35377814"))
    .source_owner(@sigstore.GitHubOwner::parse("finos"))
    .source_ref(git_ref("refs/tags/provider-snapshot/v0.2.0"))
    .hosted_runners_only()
  assert_eq(outcome(verify_morphir(all)), "pass")
  let recreated = rust_signer().repository_id(id("999"))
  let reasons = mismatches(verify_morphir(recreated))
  guard reasons is [ClaimMismatch(claim=RepositoryId, expected~, actual~)] else {
    fail("\{reasons.length()}")
  }
  assert_eq(expected, "999")
  assert_eq(actual, Some("513894754"))
  assert_true(
    mismatches(verify_morphir(rust_signer().owner_id(id("35377815")))) is
    [ClaimMismatch(claim=OwnerId, ..)],
  )
  assert_true(
    mismatches(verify_morphir(rust_signer().source_owner(@sigstore.GitHubOwner::parse("cli")))) is
    [ClaimMismatch(claim=SourceOwner, ..)],
  )
}

///|
test "scenario: source ref" {
  let policy = rust_signer().source_ref(git_ref("refs/heads/main"))
  let verdict = verify_morphir(policy)
  let reasons = mismatches(verdict)
  guard reasons is [ClaimMismatch(claim=SourceRef, expected~, actual~)] else {
    fail("\{reasons.length()}")
  }
  assert_eq(expected, "refs/heads/main")
  assert_eq(actual, Some("refs/tags/provider-snapshot/v0.2.0"))
  assert_eq(
    mismatch_message(verdict),
    "the source ref is \"refs/tags/provider-snapshot/v0.2.0\", not \"refs/heads/main\"",
  )
}

///|
test "scenario: GitHub-hosted runner" {
  assert_eq(outcome(verify_morphir(rust_signer().hosted_runners_only())), "pass")
  // github_workflow refuses self-hosted runners unless told not to.
  assert_eq(outcome(verify_morphir(morphir_policy())), "pass")
  let any_runner = @sigstore.Policy::github_workflow(
    repository("finos/morphir-rust"),
    workflow=workflow(morphir_workflow),
    hosted_runner_only=false,
  )
  assert_eq(outcome(verify_morphir(any_runner)), "pass")
}

///|
test "scenario: second publisher matches" {
  let python = @sigstore.Policy::github_workflow(
    repository("finos/morphir-python"),
    workflow=workflow(morphir_workflow),
  )
  let verdict = verify_morphir(python, alternatives=[morphir_policy()])
  guard verdict is Verified(facts) else { fail(outcome(verdict)) }
  assert_eq(facts.policy_index, 1)
  // The first policy that matches is named.
  let both = verify_morphir(morphir_policy(), alternatives=[rust_signer()])
  guard both is Verified(first) else { fail(outcome(both)) }
  assert_eq(first.policy_index, 0)
}

///|
test "a failed verdict gives the reason of each policy" {
  let python = @sigstore.Policy::github_workflow(
    repository("finos/morphir-python"),
    workflow=workflow(morphir_workflow),
  )
  let ui = @sigstore.Policy::github_workflow(
    repository("finos/morphir-ui"),
    workflow=workflow(morphir_workflow),
  )
  let wrong_ref = rust_signer().source_ref(git_ref("refs/heads/main"))
  let reasons = mismatches(verify_morphir(python, alternatives=[ui, wrong_ref]))
  guard reasons is [IdentityMismatch(expected=first, ..), IdentityMismatch(expected=second, ..), ClaimMismatch(claim=SourceRef, ..)] else {
    fail("\{reasons.length()}")
  }
  assert_true(first.contains("finos/morphir-python"))
  assert_true(second.contains("finos/morphir-ui"))
}

///|
test "the cli/cli bundles match only their own repository" {
  for case in github_cases() {
    if case.repository == "cli/cli" {
      let other = @sigstore.Policy::github_workflow(
        repository("finos/morphir-rust"),
        workflow=workflow(case.workflow),
      )
      assert_true(mismatches(verify_case(case, other)) is [IdentityMismatch(..)], msg=case.bundle)
      let pinned = @sigstore.Policy::github_workflow(
        repository(case.repository),
        workflow=workflow(case.workflow),
        git_ref=git_ref(case.git_ref),
      )
      assert_eq(outcome(verify_case(case, pinned)), "pass", msg=case.bundle)
    }
  }
}
