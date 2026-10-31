///|
/// The text of a fixture file in a generated fixture group.
fn fixture(group : Array[(String, String)], path : String) -> String {
  for file in group {
    if file.0 == path {
      return file.1
    }
  }
  abort("no fixture \{path}")
}

///|
/// One case of `testdata/github/cases.json`.
struct GitHubCase {
  bundle : String
  digest : String
  repository : String
  workflow : String
  git_ref : String
  san : String
  integrated_time : Int64
  log_index : Int64
}

///|
fn github_cases() -> Array[GitHubCase] raise {
  guard @json.parse(fixture(@fixtures.github, "cases.json")) is Array(items) else {
    fail("cases.json is not an array")
  }
  items.map(item => {
    guard item is Object(map) else { fail("a case is not an object") }
    fn text(name : String) -> String raise {
      guard map.get(name) is Some(String(value)) else { fail("no \{name}") }
      value
    }

    fn number(name : String) -> Int64 raise {
      guard map.get(name) is Some(Number(value, ..)) else { fail("no \{name}") }
      value.to_int64()
    }

    {
      bundle: text("bundle"),
      digest: text("digest"),
      repository: text("repository"),
      workflow: text("workflow"),
      git_ref: text("ref"),
      san: text("san"),
      integrated_time: number("integratedTime"),
      log_index: number("logIndex"),
    }
  })
}

///|
/// A time after every fixture was made.
let later : @sigstore.Instant = @sigstore.Instant::from_unix_seconds(1793000000L)

///|
fn case_policy(case : GitHubCase) -> @sigstore.Policy raise {
  @sigstore.Policy::github_workflow(
    @sigstore.GitHubRepository::parse(case.repository),
    workflow=@sigstore.WorkflowPath::parse(case.workflow),
  )
}

///|
fn verify_case(
  case : GitHubCase,
  policy : @sigstore.Policy,
  root? : @sigstore.TrustedRoot = @sigstore.TrustedRoot::public_good(),
) -> @sigstore.Verdict raise {
  @sigstore.verify(
    @sigstore.Bundle::parse(fixture(@fixtures.github, case.bundle)),
    @sigstore.ArtifactDigest::parse(case.digest),
    root,
    policy,
    now=later,
  )
}

///|
test "real GitHub attestations verify with the public-good root" {
  for case in github_cases() {
    match verify_case(case, case_policy(case)) {
      Verified(facts) => {
        assert_eq(facts.times[0].time.unix_seconds(), case.integrated_time)
        guard facts.times[0].source is Log(log_index~, ..) else { fail("not a log time") }
        assert_eq(log_index, case.log_index)
        assert_eq(facts.claims.subject_names, [case.san])
        assert_eq(facts.claims.issuer, Some("https://token.actions.githubusercontent.com"))
        assert_eq(facts.claims.runner_environment, Some("github-hosted"))
        assert_eq(facts.claims.source_repository_ref, Some(case.git_ref))
        guard facts.statement is Some(statement) else { fail("no statement") }
        assert_eq(statement.predicate_type, @sigstore.PredicateType::slsa_provenance_v1())
      }
      Rejected(reason) => fail("\{case.bundle}: \{reason.message()}")
    }
  }
}

///|
/// The text of a real GitHub bundle of the test data.
fn github_fixture(path : String) -> String {
  fixture(@fixtures.github, path)
}
