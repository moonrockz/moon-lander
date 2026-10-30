///|
fn parse_issuer(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.Issuer::parse(text))
}

///|
fn parse_subject_name(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.SubjectName::parse(text))
}

///|
fn parse_owner(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.GitHubOwner::parse(text))
}

///|
fn parse_repository(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.GitHubRepository::parse(text))
}

///|
fn parse_workflow(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.WorkflowPath::parse(text))
}

///|
fn parse_git_ref(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.GitRef::parse(text))
}

///|
fn parse_id(text : String) -> Unit raise @sigstore.IdentityError {
  ignore(@sigstore.GitHubId::parse(text))
}

///|
/// Check that `parse` refuses `text` with `kind` and `rule`, and that the
/// message names the input.
fn refuses(
  parse : (String) -> Unit raise @sigstore.IdentityError,
  text : String,
  kind : String,
  rule : String,
) -> Unit raise {
  let err = try parse(text) catch {
    err => err
  } noraise {
    _ => fail("\{text.escape()} parsed")
  }
  let InvalidIdentity(kind=actual_kind, text=actual_text, rule=actual_rule) = err
  assert_eq(kind_name(actual_kind), kind, msg=text)
  assert_eq(actual_text, text, msg=text)
  assert_eq(actual_rule, rule, msg=text)
  assert_true(err.message().contains(text.escape()), msg=err.message())
  assert_true(err.message().contains(rule), msg=err.message())
}

///|
/// The name of an identity kind.
fn kind_name(kind : @sigstore.IdentityKind) -> String {
  match kind {
    IssuerUrl => "IssuerUrl"
    SubjectName => "SubjectName"
    Repository => "Repository"
    Owner => "Owner"
    Workflow => "Workflow"
    Ref => "Ref"
    NumericId => "NumericId"
  }
}

///|
/// A text of `count` copies of `char`.
fn repeat(char : Char, count : Int) -> String {
  let out = StringBuilder()
  for _ in 0..<count {
    out.write_char(char)
  }
  out.to_string()
}

///|
test "scenario: repository without owner" {
  refuses(parse_repository, "morphir-rust", "Repository", "use the form owner/repo")
  let err = try @sigstore.GitHubRepository::parse("morphir-rust") catch {
    err => err
  } noraise {
    _ => fail("parsed")
  }
  assert_eq(err.message(), "Invalid repository \"morphir-rust\": use the form owner/repo")
}

///|
test "scenario: issuer without https" {
  refuses(
    parse_issuer, "http://token.actions.githubusercontent.com", "IssuerUrl", "use an https URL",
  )
}

///|
test "scenario: ref without prefix" {
  refuses(parse_git_ref, "v0.2.0", "Ref", "a ref starts with refs/ and has a name")
}

///|
test "Issuer: an https URL with a host and no spaces" {
  let issuer = @sigstore.Issuer::parse("https://token.actions.githubusercontent.com")
  assert_eq(issuer, @sigstore.Issuer::github_actions())
  assert_eq(issuer.to_string(), "https://token.actions.githubusercontent.com")
  // The shortest host.
  parse_issuer("https://a")
  refuses(parse_issuer, "", "IssuerUrl", "use an https URL")
  refuses(parse_issuer, "HTTPS://a", "IssuerUrl", "use an https URL")
  refuses(parse_issuer, "https:/a", "IssuerUrl", "use an https URL")
  refuses(parse_issuer, "https://", "IssuerUrl", "the URL has no host")
  refuses(parse_issuer, "https:///path", "IssuerUrl", "the URL has no host")
  let spaces = "the URL has a space or a control character"
  refuses(parse_issuer, "https://a b", "IssuerUrl", spaces)
  refuses(parse_issuer, "https://a\t", "IssuerUrl", spaces)
  refuses(parse_issuer, "https://a\u{7f}", "IssuerUrl", spaces)
}

///|
test "SubjectName: a non-empty text with no spaces" {
  parse_subject_name("a")
  assert_eq(
    @sigstore.SubjectName::parse("https://github.com/o/r/.github/workflows/w.yml@refs/heads/main").to_string(),
    "https://github.com/o/r/.github/workflows/w.yml@refs/heads/main",
  )
  refuses(parse_subject_name, "", "SubjectName", "the identity is empty")
  let spaces = "the identity has a space or a control character"
  refuses(parse_subject_name, "a b", "SubjectName", spaces)
  refuses(parse_subject_name, " ", "SubjectName", spaces)
  refuses(parse_subject_name, "a\n", "SubjectName", spaces)
}

///|
test "GitHubOwner: 1 to 39 letters, digits and inner '-'" {
  let length = "an owner has 1 to 39 characters"
  let chars = "an owner has only ASCII letters, digits and '-'"
  let hyphen = "an owner cannot start or end with '-'"
  parse_owner("a")
  parse_owner(repeat('a', 39))
  parse_owner("a-b")
  parse_owner("A1-b2")
  refuses(parse_owner, "", "Owner", length)
  refuses(parse_owner, repeat('a', 40), "Owner", length)
  refuses(parse_owner, "a_b", "Owner", chars)
  refuses(parse_owner, "a.b", "Owner", chars)
  refuses(parse_owner, "a/b", "Owner", chars)
  refuses(parse_owner, "é", "Owner", chars)
  refuses(parse_owner, "-a", "Owner", hyphen)
  refuses(parse_owner, "a-", "Owner", hyphen)
  refuses(parse_owner, "-", "Owner", hyphen)
}

///|
test "GitHubOwner: equality ignores ASCII case and keeps the text" {
  let lower = @sigstore.GitHubOwner::parse("finos")
  let upper = @sigstore.GitHubOwner::parse("FINOS")
  assert_eq(lower, upper)
  assert_eq(upper.to_string(), "FINOS")
  assert_true(lower != @sigstore.GitHubOwner::parse("finos2"))
}

///|
test "GitHubRepository: owner/repo with a valid owner and name" {
  let form = "use the form owner/repo"
  let length = "a repository name has 1 to 100 characters"
  let chars = "a repository name has only ASCII letters, digits, '-', '_' and '.'"
  let dots = "a repository name cannot be . or .."
  let repository = @sigstore.GitHubRepository::parse("finos/morphir-rust")
  assert_eq(repository.to_string(), "finos/morphir-rust")
  assert_eq(repository.url(), "https://github.com/finos/morphir-rust")
  assert_eq(repository.owner(), @sigstore.GitHubOwner::parse("finos"))
  parse_repository("a/b")
  parse_repository("a/" + repeat('b', 100))
  parse_repository("a/b_c.d-e")
  parse_repository("a/.github")
  refuses(parse_repository, "morphir-rust", "Repository", form)
  refuses(parse_repository, "a/b/c", "Repository", form)
  refuses(parse_repository, "", "Repository", form)
  refuses(parse_repository, "a/", "Repository", length)
  refuses(parse_repository, "a/" + repeat('b', 101), "Repository", length)
  refuses(parse_repository, "a/b c", "Repository", chars)
  refuses(parse_repository, "a/b@c", "Repository", chars)
  refuses(parse_repository, "a/.", "Repository", dots)
  refuses(parse_repository, "a/..", "Repository", dots)
  // The owner rules apply, with the repository kind.
  refuses(parse_repository, "/b", "Repository", "an owner has 1 to 39 characters")
  refuses(parse_repository, "-a/b", "Repository", "an owner cannot start or end with '-'")
  refuses(parse_repository, "a_b/c", "Repository", "an owner has only ASCII letters, digits and '-'")
}

///|
test "GitHubRepository: equality ignores ASCII case of owner and name" {
  assert_eq(
    @sigstore.GitHubRepository::parse("FINOS/Morphir-Rust"),
    @sigstore.GitHubRepository::parse("finos/morphir-rust"),
  )
  assert_true(
    @sigstore.GitHubRepository::parse("finos/morphir-rust") !=
    @sigstore.GitHubRepository::parse("finos/morphir-python"),
  )
  assert_true(
    @sigstore.GitHubRepository::parse("finos/morphir-rust") !=
    @sigstore.GitHubRepository::parse("finos2/morphir-rust"),
  )
}

///|
test "WorkflowPath: a .yml or .yaml file directly in .github/workflows/" {
  let prefix = "a workflow path starts with .github/workflows/"
  let folder = "a workflow file is directly in .github/workflows/"
  let suffix = "a workflow file ends with .yml or .yaml"
  let empty = "the workflow file name is empty"
  let chars = "a workflow path has no '@', space or control character"
  assert_eq(
    @sigstore.WorkflowPath::parse(".github/workflows/release.yml").to_string(),
    ".github/workflows/release.yml",
  )
  parse_workflow(".github/workflows/release.yaml")
  parse_workflow(".github/workflows/a.yml")
  parse_workflow(".github/workflows/.yamllint.yml")
  parse_workflow(".github/workflows/.ymlx.yaml")
  refuses(parse_workflow, "release.yml", "Workflow", prefix)
  refuses(parse_workflow, "github/workflows/release.yml", "Workflow", prefix)
  refuses(parse_workflow, "/.github/workflows/release.yml", "Workflow", prefix)
  refuses(parse_workflow, ".github/workflows/sub/release.yml", "Workflow", folder)
  refuses(parse_workflow, ".github/workflows/release.json", "Workflow", suffix)
  refuses(parse_workflow, ".github/workflows/release.YML", "Workflow", suffix)
  refuses(parse_workflow, ".github/workflows/", "Workflow", suffix)
  refuses(parse_workflow, ".github/workflows/.yml", "Workflow", empty)
  refuses(parse_workflow, ".github/workflows/.yaml", "Workflow", empty)
  refuses(parse_workflow, ".github/workflows/a@b.yml", "Workflow", chars)
  refuses(parse_workflow, ".github/workflows/a b.yml", "Workflow", chars)
}

///|
test "GitRef: refs/ and a name, with no '..' or spaces" {
  let prefix = "a ref starts with refs/ and has a name"
  let chars = "a ref has no '..', space or control character"
  assert_eq(@sigstore.GitRef::parse("refs/heads/main").to_string(), "refs/heads/main")
  parse_git_ref("refs/x")
  parse_git_ref("refs/tags/provider-snapshot/v0.2.0")
  parse_git_ref("refs/heads/a.b")
  refuses(parse_git_ref, "refs/", "Ref", prefix)
  refuses(parse_git_ref, "refs", "Ref", prefix)
  refuses(parse_git_ref, "heads/main", "Ref", prefix)
  refuses(parse_git_ref, "refs/heads/a..b", "Ref", chars)
  refuses(parse_git_ref, "refs/heads/a b", "Ref", chars)
  refuses(parse_git_ref, "refs/heads/a\n", "Ref", chars)
}

///|
test "GitHubId: 1 to 20 digits without a leading zero" {
  let length = "an ID has 1 to 20 digits"
  let digits = "an ID has only digits"
  let zero = "an ID has no leading zero"
  assert_eq(@sigstore.GitHubId::parse("513894754").to_string(), "513894754")
  parse_id("0")
  parse_id("1")
  parse_id("10")
  parse_id("1" + repeat('0', 19))
  refuses(parse_id, "", "NumericId", length)
  refuses(parse_id, "1" + repeat('0', 20), "NumericId", length)
  refuses(parse_id, "12a", "NumericId", digits)
  refuses(parse_id, "-1", "NumericId", digits)
  refuses(parse_id, "+1", "NumericId", digits)
  refuses(parse_id, " 1", "NumericId", digits)
  refuses(parse_id, "01", "NumericId", zero)
  refuses(parse_id, "00", "NumericId", zero)
}
