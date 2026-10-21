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
/// the display name, the file layouts to search, and the walk-up rule.
pub struct Conventions {
  priv name : String
  priv prefix : String
  priv display : String
  priv layouts : Array[Layout]
  priv walk_up : Bool
}

///|
/// Where a primary file sits in a directory.
priv enum Layout {
  /// `<app>.<ext>` in the directory.
  Root
}

///|
/// An empty convention set: no layouts and no walk-up. `prefix` defaults to
/// the name in upper case with `-` changed to `_`, and `display` to the name.
pub fn base(
  name : String,
  prefix? : String,
  display? : String,
) -> Conventions {
  {
    name,
    prefix: prefix.unwrap_or(name.to_upper().replace_all(old="-", new="_")),
    display: display.unwrap_or(name),
    layouts: [],
    walk_up: false,
  }
}

///|
/// The standard convention set: `base` with the `<app>.<ext>` layout and
/// walk-up from the working directory. Later parts add the other layouts and
/// the system, user, and override locations.
pub fn app_dirs(
  name : String,
  prefix? : String,
  display? : String,
) -> Conventions {
  { ..base(name, prefix?, display?), layouts: [Root], walk_up: true }
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
/// `@config.load`, discovery gives the project primary at its position in
/// merge order, with the role `Workspace` and the priority 300.
pub fn add(
  builder : @config.ConfigBuilder,
  conventions : Conventions,
) -> @config.ConfigBuilder {
  @config.provider(builder, {
    name: conventions.display,
    expand: context => discover(conventions, context),
  })
}
