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
) -> DiscoveryOptions {
  { environment, config, isolated, project }
}

///|
/// An immutable convention set: the application name, the variable prefix,
/// the display name, the standard parts to use, the walk-up rule, the stop
/// boundary, and the legacy fallback file.
pub struct Conventions {
  priv name : String
  priv prefix : String
  priv display : String
  priv parts : Array[Part]
  priv walk_up : Bool
  priv boundary : String?
  priv legacy : Legacy?
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
/// An empty convention set: no parts and no walk-up. `prefix` defaults to the
/// name in upper case with `-` changed to `_`, and `display` to the name.
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
/// primary with the role `Workspace`, `Legacy`, or `Explicit` (300), the local
/// override (390), and the user override (400).
///
/// Discovery reads `isolated` and `config` from `options`. In isolated mode the
/// system, global user, and override sources report `Skipped`. `Explicit(path)`
/// is the project primary with no walk-up, and `Skip` skips it. Discovery does
/// not read the `environment` and `project` options yet; a given value adds a
/// `Note` warning so that it is never ignored without a sign.
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
