///|
/// The discovery inputs that a host gives from its arguments. Every field
/// defaults to "not given". Discovery never reads the arguments itself.
pub(all) struct DiscoveryOptions {
  /// The environment name, for example from `--environment`.
  environment : String?
  /// The project primary, for example `Explicit(path)` from `--config`.
  config : @config.SourceSelection[String]
  /// Skip the user and machine files, for example from `--isolated`.
  isolated : Bool
  /// The project selector, for example from `--project`.
  project : String?
  /// Explicit profile selection; profiles remain opt-in.
  profiles : @config.ProfileSelection
} derive(Eq, Debug)

///|
pub extend DiscoveryOptions with Eq::{equal, not_equal}

///|
pub extend DiscoveryOptions with @debug.Debug::{to_repr}

///|
/// Options with every field not given.
pub fn DiscoveryOptions::new(
  environment? : String,
  config? : @config.SourceSelection[String] = Discover,
  isolated? : Bool = false,
  project? : String,
  profiles? : @config.ProfileSelection = Unspecified,
) -> DiscoveryOptions {
  { environment, config, isolated, project, profiles }
}

///|
/// An immutable convention set: the application name, the variable prefix,
/// the display name, the standard parts to use, the walk-up rule, the stop
/// boundary, the legacy fallback file, the environment opt-in, the workspace
/// keys, and the key filters.
pub struct Conventions {
  priv name : String
  priv prefix : String
  priv display : String
  priv parts : Array[Part]
  priv walk_up : Bool
  priv boundary : String?
  priv legacy : Legacy?
  priv environments : Environments?
  priv profiles : @profiles.Policy?
  priv workspace : WorkspaceKeys?
  priv member_scope : Array[String]
  priv inherited : Array[String]
  priv root_policy : RootPolicy
  priv member_loading : MemberLoading
  priv layers : FormatLayers?
  priv selected_file : SelectedFilePolicy
}

///|
/// A standard part of a convention set, which `without` can remove.
pub(all) enum Part {
  /// The system directory: `/etc/<app>`, or `%PROGRAMDATA%/<app>` on Windows.
  SystemDir
  /// `<app>/<app>.<ext>` in the global user configuration directory.
  UserConfigDir
  /// `<app>.<ext>` in the application home, `$<PREFIX>_HOME` or `~/.<app>`.
  AppHome
  /// The three primary layouts at each discovery location.
  Layouts
  /// `*.local.*` files next to each primary.
  LocalOverrides
  /// `*.user.*` files next to each primary.
  UserOverrides
} derive(Eq, Debug)

///|
pub extend Part with Eq::{equal, not_equal}

///|
pub extend Part with @debug.Debug::{to_repr}

///|
/// Where a primary file sits in a directory.
priv enum Layout {
  /// `<app>.<ext>` in the directory.
  Root
  /// `.<app>/<app>.<ext>`.
  Hidden
  /// `.config/<app>/config.<ext>`.
  DotConfig
}

///|
/// A legacy fallback file: its name, its own format, and a decoder from the
/// parsed value to a configuration layer.
priv struct Legacy {
  name : String
  format : @config.Format
  decode : (@config.ConfigValue) -> @config.ConfigValue raise @config.ConfigError
}

///|
/// The environment opt-in and its default name.
priv struct Environments {
  default : String?
}

///|
/// The key paths of the workspace values, in the text form of a key path.
priv struct WorkspaceKeys {
  members : String
  exclude : String
  default_member : String
  project_name : String
}

///|
/// An empty convention set: no parts, no walk-up, no environments and no
/// workspace.
/// `prefix` defaults to the name in upper case with `-` changed to `_`, and
/// `display` to the name.
pub fn base(
  name : String,
  prefix? : String,
  display? : String,
) -> Conventions {
  {
    name,
    prefix: prefix.unwrap_or(name.to_upper().replace_all(old="-", new="_")),
    display: display.unwrap_or(name),
    parts: [],
    walk_up: false,
    boundary: None,
    legacy: None,
    environments: None,
    profiles: None,
    workspace: None,
    member_scope: [],
    inherited: [],
    root_policy: NearestFile,
    member_loading: Automatic,
    layers: None,
    selected_file: Primary,
  }
}

///|
/// The standard convention set: `base` with every standard part (the system
/// directory, the global user directory, the application home, the three
/// primary layouts, local overrides, and user overrides) and walk-up from the
/// working directory.
pub fn app_dirs(
  name : String,
  prefix? : String,
  display? : String,
) -> Conventions {
  {
    ..base(name, prefix?, display?),
    parts: [
      SystemDir, UserConfigDir, AppHome, Layouts, LocalOverrides, UserOverrides,
    ],
    walk_up: true,
  }
}

///|
/// Add the system directory: `/etc/<app>` on Linux and macOS, and
/// `%PROGRAMDATA%/<app>` on Windows, or `C:/ProgramData/<app>` when
/// `PROGRAMDATA` is not set. The candidates are `<app>.<ext>`.
pub fn system_dir(conventions : Conventions) -> Conventions {
  conventions.with_part(SystemDir)
}

///|
/// Add the global user configuration directory: `$XDG_CONFIG_HOME` when it is
/// absolute, else `$HOME/.config` on Linux and
/// `$HOME/Library/Application Support` on macOS, and `%APPDATA%` on Windows.
/// The candidates are `<app>/<app>.<ext>`.
pub fn user_config_dir(conventions : Conventions) -> Conventions {
  conventions.with_part(UserConfigDir)
}

///|
/// Add the application home: `$<PREFIX>_HOME`, else `.<app>` in the user home
/// (`$HOME`, or `%USERPROFILE%` on Windows). The candidates are `<app>.<ext>`.
/// The application home and the user configuration directory are one global
/// source, so two global files are `Ambiguous`.
pub fn app_home(conventions : Conventions) -> Conventions {
  conventions.with_part(AppHome)
}

///|
/// Add the three primary layouts: `<app>.<ext>`, `.<app>/<app>.<ext>`, and
/// `.config/<app>/config.<ext>`.
pub fn layouts(conventions : Conventions) -> Conventions {
  conventions.with_part(Layouts)
}

///|
/// Add local overrides: `<app>.local.<ext>` next to a primary in the
/// `<app>.<ext>` or `.<app>/<app>.<ext>` layout, and `config.local.<ext>` next
/// to `.config/<app>/config.<ext>`, with the role `LocalOverride` and the
/// priority 390.
pub fn local_overrides(conventions : Conventions) -> Conventions {
  conventions.with_part(LocalOverrides)
}

///|
/// Add user overrides: `<app>.user.<ext>` next to a primary in the
/// `<app>.<ext>` or `.<app>/<app>.<ext>` layout, and `config.user.<ext>` next
/// to `.config/<app>/config.<ext>`, with the role `UserOverride` and the
/// priority 400.
pub fn user_overrides(conventions : Conventions) -> Conventions {
  conventions.with_part(UserOverrides)
}

///|
/// Remove one standard part, for example `without(SystemDir)`.
pub fn without(conventions : Conventions, part : Part) -> Conventions {
  { ..conventions, parts: conventions.parts.filter(p => p != part) }
}

///|
fn Conventions::with_part(self : Conventions, part : Part) -> Conventions {
  if self.parts.contains(part) {
    self
  } else {
    { ..self, parts: [..self.parts, part] }
  }
}

///|
fn Conventions::has(self : Conventions, part : Part) -> Bool {
  self.parts.contains(part)
}

///|
/// Stop the walk-up at `dir`: discovery looks in `dir` and never above it. A
/// relative `dir` joins the working directory. A working directory outside
/// `dir` raises `OutsideBoundary`.
pub fn boundary(conventions : Conventions, dir : String) -> Conventions {
  { ..conventions, boundary: Some(dir) }
}

///|
/// Add a legacy fallback file, for example `acme.json`. At a location with no
/// primary file, the legacy file is the primary and marks the project root.
/// `format` parses it and is not registered, so its extensions never join the
/// searched extensions. `decode` turns the parsed value into a layer.
pub fn legacy(
  conventions : Conventions,
  name : String,
  format~ : @config.Format,
  decode~ : (@config.ConfigValue) -> @config.ConfigValue raise @config.ConfigError,
) -> Conventions {
  { ..conventions, legacy: Some({ name, format, decode }) }
}

///|
/// Turn on workspaces. A project file whose value sets `members` or
/// `default_member` is a workspace. Its members are the directories that the
/// member entries select, without the entries of `exclude`. Each argument is a
/// key path in text form. Discovery reads the members, the exclude entries
/// and the default member from the merged value of the system file, the
/// global user file and the workspace primary, and the project name from the
/// same value or from the primary of a member.
///
/// In an entry, `*` matches any run of characters in one segment, `**`
/// matches zero or more whole segments, and every other character matches
/// itself. An absolute entry, an entry with a drive, a `\` or a `..`
/// segment gives a `Note` warning, and discovery skips it. The workspace root
/// is never its own member.
pub fn workspace(
  conventions : Conventions,
  members? : String = "workspace.members",
  exclude? : String = "workspace.exclude",
  default_member? : String = "workspace.default_member",
  project_name? : String = "project.name",
) -> Conventions {
  {
    ..conventions,
    workspace: Some({ members, exclude, default_member, project_name }),
  }
}

///|
/// Remove the key paths `paths` from each member layer: the member primary
/// and its environment and profile files, local override and user override. Only the
/// workspace can set them. A removed key gives a `KeyRemoved` warning in the
/// report of that source, and it has no origin. Each path is the text form
/// of a key path, for example `workspace.out_dir`.
pub fn member_scope_keys(
  conventions : Conventions,
  paths : Array[String],
) -> Conventions {
  { ..conventions, member_scope: [..conventions.member_scope, ..paths] }
}

///|
/// Remove the keys `keys` from the layers that a selected member inherits:
/// the system file, the global user file, the workspace primary and its
/// environment and profile files, local override and user override. The removal gives no
/// warning. With no selected member, every layer stays complete. Each key is
/// the text form of a key path, usually a top-level key such as `project`.
pub fn inherited_filter(
  conventions : Conventions,
  keys : Array[String],
) -> Conventions {
  { ..conventions, inherited: [..conventions.inherited, ..keys] }
}

///|
/// The application name.
pub fn Conventions::name(self : Conventions) -> String {
  self.name
}

///|
/// The prefix of the application's environment variables.
pub fn Conventions::prefix(self : Conventions) -> String {
  self.prefix
}

///|
/// The display name, which the ambiguity message shows.
pub fn Conventions::display(self : Conventions) -> String {
  self.display
}

///|
/// Add the convention set to a core builder as a source provider. During
/// `@config.load`, discovery gives its sources at its position in merge order:
/// the system source (priority 100), the global user source (200), the project
/// or workspace primary with the role `Workspace`, `Legacy`, or `Explicit`
/// (300), the selected member primary with the role `Member` (350), the
/// environment files (375), profile files (380), local overrides (390), and user overrides
/// (400). Each kind of adjacent file loads for the workspace, then for the
/// member, for each active name in the profile stage.
///
/// Discovery reads `isolated`, `config`, `environment`, `profiles` and `project` from
/// `options`. In isolated mode the system, global user, and override sources
/// report `Skipped`. `Explicit(path)` is the project primary with no walk-up,
/// and `Skip` skips it. `project` selects a workspace member by its path or
/// by its project name. With environments off, a given `environment` adds a
/// `Note` warning, and with no workspace part a given `project` does too.
pub fn add(
  builder : @config.ConfigBuilder,
  conventions : Conventions,
  options? : DiscoveryOptions = DiscoveryOptions::new(),
) -> @config.ConfigBuilder {
  @config.provider(builder, {
    name: conventions.display,
    expand: context => discover(conventions, options, context),
  })
}

///|
/// Enable independent configuration profiles with an immutable policy.
pub fn profiles(conventions : Conventions, policy : @profiles.Policy) -> Conventions {
  { ..conventions, profiles: Some(policy) }
}

///|
/// Set the root selection policy. NearestFile retains the legacy discovery
/// behavior. WorkspaceFirst inspects documents up to the first declared section.
pub fn root_policy(conventions : Conventions, policy : RootPolicy) -> Conventions {
  { ..conventions, root_policy: policy }
}

///|
/// Select automatic single-member loading or leave the member walk to the caller.
pub fn member_loading(conventions : Conventions, loading : MemberLoading) -> Conventions {
  { ..conventions, member_loading: loading }
}

///|
/// Whether this convention set reserves profile controls and its selector.
pub fn Conventions::profiles_enabled(self : Conventions) -> Bool { self.profiles is Some(_) }

///|
/// How an explicit config selection participates in discovery.
pub(all) enum SelectedFilePolicy {
  /// Use it as the project primary without walk-up (the default).
  Primary
  /// Retain discovery and move the selected file to one Explicit layer at 325.
  Overlay
} derive(Eq, Debug)

///|
pub extend SelectedFilePolicy with Eq::{equal, not_equal}

///|
pub extend SelectedFilePolicy with @debug.Debug::{to_repr}

///|
/// Select explicit-primary compatibility or an overlay above base primaries
/// and below members. Overlay paths resolve against the supplied working directory.
pub fn selected_file_policy(conventions : Conventions, policy : SelectedFilePolicy) -> Conventions {
  { ..conventions, selected_file: policy }
}
