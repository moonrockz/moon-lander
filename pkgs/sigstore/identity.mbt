///|
/// The kind of identity value that a text failed to parse as.
pub enum IdentityKind {
  IssuerUrl
  SubjectName
  Repository
  Owner
  Workflow
  Ref
  NumericId
} derive(Eq, Debug)

///|
pub extend IdentityKind with Eq::{equal, not_equal}

///|
pub extend IdentityKind with @debug.Debug::{to_repr}

///|
/// A text that is not a valid identity value.
pub suberror IdentityError {
  /// The text `text` is not a valid `kind`: it breaks `rule`.
  InvalidIdentity(kind~ : IdentityKind, text~ : String, rule~ : String)
} derive(Debug)

///|
pub extend IdentityError with @debug.Debug::{to_repr}

///|
pub fn IdentityError::message(self : IdentityError) -> String {
  let InvalidIdentity(kind~, text~, rule~) = self
  let name = match kind {
    IssuerUrl => "issuer"
    SubjectName => "certificate identity"
    Repository => "repository"
    Owner => "repository owner"
    Workflow => "workflow path"
    Ref => "Git ref"
    NumericId => "GitHub ID"
  }
  "Invalid \{name} \{text.escape()}: \{rule}"
}

///|
fn has_space_or_control(text : String) -> Bool {
  text.iter().any(char => char.to_int() <= 0x20 || char.to_int() == 0x7f)
}

///|
/// An OIDC issuer URL, for example `https://token.actions.githubusercontent.com`.
pub struct Issuer {
  priv url : String
} derive(Eq, Debug)

///|
pub extend Issuer with Eq::{equal, not_equal}

///|
pub extend Issuer with @debug.Debug::{to_repr}

///|
/// Parse an issuer: an `https` URL with a host and no spaces.
pub fn Issuer::parse(text : String) -> Issuer raise IdentityError {
  let fail = rule => InvalidIdentity(kind=IssuerUrl, text~, rule~)
  guard text.has_prefix("https://") else { raise fail("use an https URL") }
  guard text.length() > 8 && text[8] != '/' else { raise fail("the URL has no host") }
  guard !has_space_or_control(text) else { raise fail("the URL has a space or a control character") }
  { url: text }
}

///|
/// The GitHub Actions OIDC issuer.
pub fn Issuer::github_actions() -> Issuer {
  { url: "https://token.actions.githubusercontent.com" }
}

///|
pub impl Show for Issuer with output(self, logger) {
  logger.write_string(self.url)
}

///|
pub extend Issuer with Show::{output, to_string}

///|
/// An exact certificate identity: the URI or email subject alternative name.
pub struct SubjectName {
  priv text : String
} derive(Eq, Debug)

///|
pub extend SubjectName with Eq::{equal, not_equal}

///|
pub extend SubjectName with @debug.Debug::{to_repr}

///|
/// Parse a certificate identity: a non-empty text with no spaces.
pub fn SubjectName::parse(text : String) -> SubjectName raise IdentityError {
  guard !text.is_empty() else {
    raise InvalidIdentity(kind=SubjectName, text~, rule="the identity is empty")
  }
  guard !has_space_or_control(text) else {
    raise InvalidIdentity(kind=SubjectName, text~, rule="the identity has a space or a control character")
  }
  { text, }
}

///|
pub impl Show for SubjectName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend SubjectName with Show::{output, to_string}

///|
fn owner_rule(owner : StringView) -> String? {
  guard owner.length() >= 1 && owner.length() <= 39 else {
    return Some("an owner has 1 to 39 characters")
  }
  guard owner.iter().all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-') else {
    return Some("an owner has only ASCII letters, digits and '-'")
  }
  guard !owner.has_prefix("-") && !owner.has_suffix("-") else {
    return Some("an owner cannot start or end with '-'")
  }
  None
}

///|
/// A GitHub account name, for example `finos`.
pub struct GitHubOwner {
  priv name : String
} derive(Debug)

///|
pub extend GitHubOwner with @debug.Debug::{to_repr}

///|
/// GitHub names are case-insensitive, so equality ignores ASCII case.
pub impl Eq for GitHubOwner with equal(self, other) {
  self.name.to_lower() == other.name.to_lower()
}

///|
pub extend GitHubOwner with Eq::{equal, not_equal}

///|
/// Parse a GitHub account name.
pub fn GitHubOwner::parse(text : String) -> GitHubOwner raise IdentityError {
  if owner_rule(text) is Some(rule) {
    raise InvalidIdentity(kind=Owner, text~, rule~)
  }
  { name: text }
}

///|
pub impl Show for GitHubOwner with output(self, logger) {
  logger.write_string(self.name)
}

///|
pub extend GitHubOwner with Show::{output, to_string}

///|
/// A GitHub repository, for example `finos/morphir-rust`.
pub struct GitHubRepository {
  priv owner : GitHubOwner
  priv name : String
} derive(Debug)

///|
pub extend GitHubRepository with @debug.Debug::{to_repr}

///|
/// GitHub names are case-insensitive, so equality ignores ASCII case.
pub impl Eq for GitHubRepository with equal(self, other) {
  self.owner == other.owner && self.name.to_lower() == other.name.to_lower()
}

///|
pub extend GitHubRepository with Eq::{equal, not_equal}

///|
/// Parse a repository in the form `owner/repo`.
pub fn GitHubRepository::parse(text : String) -> GitHubRepository raise IdentityError {
  let fail = rule => InvalidIdentity(kind=Repository, text~, rule~)
  let parts = text.split("/").collect()
  guard parts.length() == 2 else { raise fail("use the form owner/repo") }
  if owner_rule(parts[0]) is Some(rule) {
    raise fail(rule)
  }
  let name = parts[1]
  guard name.length() >= 1 && name.length() <= 100 else {
    raise fail("a repository name has 1 to 100 characters")
  }
  guard name.iter().all(c => c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '-' || c == '_' || c == '.') else {
    raise fail("a repository name has only ASCII letters, digits, '-', '_' and '.'")
  }
  guard name != "." && name != ".." else { raise fail("a repository name cannot be . or ..") }
  { owner: { name: parts[0].to_owned() }, name: name.to_owned() }
}

///|
/// The owner of the repository.
pub fn GitHubRepository::owner(self : GitHubRepository) -> GitHubOwner {
  self.owner
}

///|
/// The repository URL, `https://github.com/owner/repo`.
pub fn GitHubRepository::url(self : GitHubRepository) -> String {
  "https://github.com/\{self.owner}/\{self.name}"
}

///|
pub impl Show for GitHubRepository with output(self, logger) {
  logger.write_string("\{self.owner}/\{self.name}")
}

///|
pub extend GitHubRepository with Show::{output, to_string}

///|
/// A workflow file in a repository, for example
/// `.github/workflows/release.yml`.
pub struct WorkflowPath {
  priv path : String
} derive(Eq, Debug)

///|
pub extend WorkflowPath with Eq::{equal, not_equal}

///|
pub extend WorkflowPath with @debug.Debug::{to_repr}

///|
let workflow_folder : String = ".github/workflows/"

///|
/// Parse a workflow path: a `.yml` or `.yaml` file directly in
/// `.github/workflows/`.
pub fn WorkflowPath::parse(text : String) -> WorkflowPath raise IdentityError {
  let fail = rule => InvalidIdentity(kind=Workflow, text~, rule~)
  guard text.has_prefix(workflow_folder) else {
    raise fail("a workflow path starts with .github/workflows/")
  }
  let file = text[workflow_folder.length():]
  guard !file.contains("/") else { raise fail("a workflow file is directly in .github/workflows/") }
  guard file.has_suffix(".yml") || file.has_suffix(".yaml") else {
    raise fail("a workflow file ends with .yml or .yaml")
  }
  guard file != ".yml" && file != ".yaml" else {
    raise fail("the workflow file name is empty")
  }
  guard !file.contains("@") && !has_space_or_control(text) else {
    raise fail("a workflow path has no '@', space or control character")
  }
  { path: text }
}

///|
pub impl Show for WorkflowPath with output(self, logger) {
  logger.write_string(self.path)
}

///|
pub extend WorkflowPath with Show::{output, to_string}

///|
/// A fully qualified Git ref, for example `refs/tags/v1.0.0`.
pub struct GitRef {
  priv text : String
} derive(Eq, Debug)

///|
pub extend GitRef with Eq::{equal, not_equal}

///|
pub extend GitRef with @debug.Debug::{to_repr}

///|
/// Parse a Git ref: `refs/` and a name with no spaces and no `..`.
pub fn GitRef::parse(text : String) -> GitRef raise IdentityError {
  let fail = rule => InvalidIdentity(kind=Ref, text~, rule~)
  guard text.has_prefix("refs/") && text.length() > 5 else {
    raise fail("a ref starts with refs/ and has a name")
  }
  guard !text.contains("..") && !has_space_or_control(text) else {
    raise fail("a ref has no '..', space or control character")
  }
  { text, }
}

///|
pub impl Show for GitRef with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend GitRef with Show::{output, to_string}

///|
/// A numeric GitHub repository or account ID, for example `513894754`. A
/// deleted and recreated repository keeps its name and gets a new ID.
pub struct GitHubId {
  priv text : String
} derive(Eq, Debug)

///|
pub extend GitHubId with Eq::{equal, not_equal}

///|
pub extend GitHubId with @debug.Debug::{to_repr}

///|
/// Parse an ID: 1 to 20 decimal digits without a leading zero.
pub fn GitHubId::parse(text : String) -> GitHubId raise IdentityError {
  let fail = rule => InvalidIdentity(kind=NumericId, text~, rule~)
  guard text.length() >= 1 && text.length() <= 20 else { raise fail("an ID has 1 to 20 digits") }
  guard text.iter().all(c => c.is_ascii_digit()) else { raise fail("an ID has only digits") }
  guard text == "0" || !text.has_prefix("0") else { raise fail("an ID has no leading zero") }
  { text, }
}

///|
pub impl Show for GitHubId with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend GitHubId with Show::{output, to_string}
