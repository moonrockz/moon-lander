///|
/// The identity claims of a Fulcio certificate. Each value is the text of its
/// extension (`1.3.6.1.4.1.57264.1.*`), or `None` when the extension is absent.
pub struct CertificateClaims {
  /// The OIDC issuer (`.1.8`, else `.1.1`).
  issuer : String?
  /// The URI or email subject alternative names.
  subject_names : Array[String]
  build_signer_uri : String?
  build_signer_digest : String?
  runner_environment : String?
  source_repository_uri : String?
  source_repository_digest : String?
  source_repository_ref : String?
  source_repository_identifier : String?
  source_repository_owner_uri : String?
  source_repository_owner_identifier : String?
  build_config_uri : String?
  build_config_digest : String?
  build_trigger : String?
  run_invocation_uri : String?
  source_repository_visibility : String?
} derive(Eq, Debug)

///|
pub extend CertificateClaims with Eq::{equal, not_equal}

///|
pub extend CertificateClaims with @debug.Debug::{to_repr}

///|
fn read_claims(leaf : @x509.Certificate) -> CertificateClaims raise @x509.X509Error {
  fn claim(arc : Int) -> String? raise @x509.X509Error {
    match leaf.extension("1.3.6.1.4.1.57264.1.\{arc}") {
      Some(extension) => Some(@x509.fulcio_value(extension))
      None => None
    }
  }

  let issuer = match claim(8) {
    Some(value) => Some(value)
    None => claim(1)
  }
  {
    issuer,
    subject_names: [..leaf.san_uris, ..leaf.san_emails],
    build_signer_uri: claim(9),
    build_signer_digest: claim(10),
    runner_environment: claim(11),
    source_repository_uri: claim(12),
    source_repository_digest: claim(13),
    source_repository_ref: claim(14),
    source_repository_identifier: claim(15),
    source_repository_owner_uri: claim(16),
    source_repository_owner_identifier: claim(17),
    build_config_uri: claim(18),
    build_config_digest: claim(19),
    build_trigger: claim(20),
    run_invocation_uri: claim(21),
    source_repository_visibility: claim(22),
  }
}

///|
priv enum Identity {
  ExactName(SubjectName)
  SignerWorkflow(GitHubRepository, WorkflowPath, GitRef?)
}

///|
/// A publisher identity that a signing certificate must have. A policy is an
/// immutable value; each method returns a new policy with one more claim.
pub struct Policy {
  priv issuer : Issuer
  priv identity : Identity
  priv source_repository : GitHubRepository?
  priv source_owner : GitHubOwner?
  priv repository_id : GitHubId?
  priv owner_id : GitHubId?
  priv source_ref : GitRef?
  priv hosted_runner_only : Bool
}

///|
fn Policy::new(issuer : Issuer, identity : Identity) -> Policy {
  {
    issuer,
    identity,
    source_repository: None,
    source_owner: None,
    repository_id: None,
    owner_id: None,
    source_ref: None,
    hosted_runner_only: false,
  }
}

///|
/// A policy that requires the exact subject alternative name `name`.
pub fn Policy::subject_name(
  name : SubjectName,
  issuer? : Issuer = Issuer::github_actions(),
) -> Policy {
  Policy::new(issuer, ExactName(name))
}

///|
/// A policy that requires the signer workflow `path` in `repository`, at `git_ref`
/// when it is given, else at any ref. It matches the SAN
/// `https://github.com/<owner>/<repo>/<path>@<git_ref>`.
pub fn Policy::signer_workflow(
  repository : GitHubRepository,
  path : WorkflowPath,
  git_ref? : GitRef,
  issuer? : Issuer = Issuer::github_actions(),
) -> Policy {
  Policy::new(issuer, SignerWorkflow(repository, path, git_ref))
}

///|
/// The usual policy for a GitHub release: the workflow `workflow` of
/// `repository` signed it, from the source of that repository, on a
/// GitHub-hosted runner unless `hosted_runner_only` is false.
pub fn Policy::github_workflow(
  repository : GitHubRepository,
  workflow~ : WorkflowPath,
  git_ref? : GitRef,
  hosted_runner_only? : Bool = true,
) -> Policy {
  let policy = Policy::signer_workflow(repository, workflow, git_ref?).source_repository(
    repository,
  )
  if hosted_runner_only {
    policy.hosted_runners_only()
  } else {
    policy
  }
}

///|
/// Also require the source repository claim (`.1.12`).
pub fn Policy::source_repository(self : Policy, repository : GitHubRepository) -> Policy {
  { ..self, source_repository: Some(repository) }
}

///|
/// Also require the source repository owner claim (`.1.16`).
pub fn Policy::source_owner(self : Policy, owner : GitHubOwner) -> Policy {
  { ..self, source_owner: Some(owner) }
}

///|
/// Also require the source repository ID claim (`.1.15`).
pub fn Policy::repository_id(self : Policy, id : GitHubId) -> Policy {
  { ..self, repository_id: Some(id) }
}

///|
/// Also require the source repository owner ID claim (`.1.17`).
pub fn Policy::owner_id(self : Policy, id : GitHubId) -> Policy {
  { ..self, owner_id: Some(id) }
}

///|
/// Also require the source ref claim (`.1.14`).
pub fn Policy::source_ref(self : Policy, git_ref : GitRef) -> Policy {
  { ..self, source_ref: Some(git_ref) }
}

///|
/// Also require the runner environment `github-hosted` (`.1.11`).
pub fn Policy::hosted_runners_only(self : Policy) -> Policy {
  { ..self, hosted_runner_only: true }
}

///|
/// A certificate claim that a policy can require.
pub enum Claim {
  SourceRepository
  SourceOwner
  RepositoryId
  OwnerId
  SourceRef
} derive(Eq, Debug)

///|
pub extend Claim with Eq::{equal, not_equal}

///|
pub extend Claim with @debug.Debug::{to_repr}

///|
/// Why a certificate does not match one policy.
pub enum PolicyMismatch {
  /// The certificate issuer is `actual`, not `expected`.
  IssuerMismatch(expected~ : String, actual~ : String?)
  /// No subject alternative name of the certificate matches `expected`.
  IdentityMismatch(expected~ : String, actual~ : Array[String])
  /// The claim `claim` is `actual`, not `expected`.
  ClaimMismatch(claim~ : Claim, expected~ : String, actual~ : String?)
  /// The policy requires a GitHub-hosted runner; the certificate gives `actual`.
  RunnerEnvironment(actual~ : String?)
} derive(Eq, Debug)

///|
pub extend PolicyMismatch with Eq::{equal, not_equal}

///|
pub extend PolicyMismatch with @debug.Debug::{to_repr}

///|
pub fn PolicyMismatch::message(self : PolicyMismatch) -> String {
  fn shown(value : String?) -> String {
    match value {
      Some(text) => text.escape()
      None => "nothing"
    }
  }

  match self {
    IssuerMismatch(expected~, actual~) =>
      "the issuer is \{shown(actual)}, not \{expected.escape()}"
    IdentityMismatch(expected~, actual~) =>
      "the certificate identity \{actual.map(name => name.escape()).join(", ")} does not match \{expected.escape()}"
    ClaimMismatch(claim~, expected~, actual~) => {
      let name = match claim {
        SourceRepository => "source repository"
        SourceOwner => "source repository owner"
        RepositoryId => "repository ID"
        OwnerId => "owner ID"
        SourceRef => "source ref"
      }
      "the \{name} is \{shown(actual)}, not \{expected.escape()}"
    }
    RunnerEnvironment(actual~) =>
      "the runner environment is \{shown(actual)}, not \"github-hosted\""
  }
}

///|
fn equal_ignoring_case(a : String?, b : String) -> Bool {
  a is Some(text) && text.to_lower() == b.to_lower()
}

///|
/// The first reason that `claims` does not match the policy, or `None`.
fn Policy::mismatch(self : Policy, claims : CertificateClaims) -> PolicyMismatch? {
  let issuer = self.issuer.to_string()
  guard claims.issuer == Some(issuer) else {
    return Some(IssuerMismatch(expected=issuer, actual=claims.issuer))
  }
  match self.identity {
    ExactName(name) => {
      let expected = name.to_string()
      guard claims.subject_names.contains(expected) else {
        return Some(IdentityMismatch(expected~, actual=claims.subject_names))
      }
    }
    SignerWorkflow(repository, path, git_ref) => {
      let prefix = "\{repository.url()}/\{path}@"
      let expected = match git_ref {
        Some(git_ref) => prefix + git_ref.to_string()
        None => prefix + "*"
      }
      let matches = claims.subject_names.iter().any(name => {
        // Owner and repository names are case-insensitive; the path and ref are not.
        guard name.length() > prefix.length() else { return false }
        let head = name[:repository.url().length()].to_owned()
        let tail = name[repository.url().length():].to_owned()
        guard head.to_lower() == repository.url().to_lower() &&
          tail.has_prefix("/\{path}@") else {
          return false
        }
        let actual_ref = tail["/\{path}@".length():].to_owned()
        match git_ref {
          Some(git_ref) => actual_ref == git_ref.to_string()
          None => actual_ref.has_prefix("refs/")
        }
      })
      guard matches else {
        return Some(IdentityMismatch(expected~, actual=claims.subject_names))
      }
    }
  }
  if self.source_repository is Some(repository) {
    guard equal_ignoring_case(claims.source_repository_uri, repository.url()) else {
      return Some(
        ClaimMismatch(
          claim=SourceRepository,
          expected=repository.url(),
          actual=claims.source_repository_uri,
        ),
      )
    }
  }
  if self.source_owner is Some(owner) {
    let expected = "https://github.com/\{owner}"
    guard equal_ignoring_case(claims.source_repository_owner_uri, expected) else {
      return Some(
        ClaimMismatch(
          claim=SourceOwner,
          expected~,
          actual=claims.source_repository_owner_uri,
        ),
      )
    }
  }
  if self.repository_id is Some(id) {
    guard claims.source_repository_identifier == Some(id.to_string()) else {
      return Some(
        ClaimMismatch(
          claim=RepositoryId,
          expected=id.to_string(),
          actual=claims.source_repository_identifier,
        ),
      )
    }
  }
  if self.owner_id is Some(id) {
    guard claims.source_repository_owner_identifier == Some(id.to_string()) else {
      return Some(
        ClaimMismatch(
          claim=OwnerId,
          expected=id.to_string(),
          actual=claims.source_repository_owner_identifier,
        ),
      )
    }
  }
  if self.source_ref is Some(git_ref) {
    guard claims.source_repository_ref == Some(git_ref.to_string()) else {
      return Some(
        ClaimMismatch(
          claim=SourceRef,
          expected=git_ref.to_string(),
          actual=claims.source_repository_ref,
        ),
      )
    }
  }
  if self.hosted_runner_only {
    guard claims.runner_environment == Some("github-hosted") else {
      return Some(RunnerEnvironment(actual=claims.runner_environment))
    }
  }
  None
}
