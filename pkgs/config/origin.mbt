///|
/// The role of a file source. Reports and error text show a role by its report
/// name, for example `user-override`.
pub(all) enum FileRole {
  Explicit
  System
  Global
  Workspace
  Member
  EnvironmentFile
  ProfileFile(ProfileName)
  LocalOverride
  UserOverride
  Legacy
} derive(Eq, Debug)

///|
pub extend FileRole with Eq::{equal, not_equal}

///|
pub extend FileRole with @debug.Debug::{to_repr}

///|
/// The kind of a configuration source.
pub(all) enum SourceKind {
  Defaults
  InMemory
  File(FileRole)
  Environment
  Overrides
} derive(Eq, Debug)

///|
pub extend SourceKind with Eq::{equal, not_equal}

///|
pub extend SourceKind with @debug.Debug::{to_repr}

///|
/// The source that set a value: its kind, display name, display priority, and
/// location. The location is a file path in the `/` form or an environment
/// variable name.
pub(all) struct Origin {
  kind : SourceKind
  source : String
  priority : Int
  location : String?
} derive(Eq, Debug)

///|
pub extend Origin with Eq::{equal, not_equal}

///|
pub extend Origin with @debug.Debug::{to_repr}

///|
/// The report name of a source kind, as Morphir names its layers. A file
/// source shows the name of its role: `project` for workspace, explicit, and
/// legacy files.
pub fn SourceKind::report_name(self : SourceKind) -> String {
  match self {
    Defaults => "defaults"
    InMemory => "in-memory"
    File(System) => "system"
    File(Global) => "global"
    File(Workspace | Explicit | Legacy) => "project"
    File(Member) => "workspace-member"
    File(EnvironmentFile) => "environment-file"
    File(ProfileFile(_)) => "profile-file"
    File(LocalOverride) => "local-override"
    File(UserOverride) => "user-override"
    Environment => "environment"
    Overrides => "overrides"
  }
}

///|
/// Text for people that names an origin: the role name and the path of a file,
/// `environment` and the variable name, or else the kind name.
fn origin_text(origin : Origin) -> String {
  match (origin.kind, origin.location) {
    (File(_) as kind, Some(path)) => "\{kind.report_name()} \{path}"
    (Environment, Some(variable)) => "environment \{variable}"
    (kind, _) => kind.report_name()
  }
}
