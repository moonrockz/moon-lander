///|
/// A system or global user source and the candidates that it checks. A
/// skipped source has no candidates.
priv struct MachineSource {
  source : @config.ConfigSource
  candidates : Array[@config.FileTreePath]
}

///|
/// The system and global user sources, in merge order. In isolated mode, or
/// with no platform, each source that the convention set uses reports
/// `Skipped`; with no platform, discovery also adds a note.
fn Conventions::machine_sources(
  self : Conventions,
  options : DiscoveryOptions,
  context : @config.LoadContext,
  extensions : Array[String],
  notes : Array[@config.ConfigWarning],
) -> Array[MachineSource] raise @config.ConfigError {
  let roles : Array[@config.FileRole] = []
  if self.has(SystemDir) {
    roles.push(System)
  }
  if self.has(UserConfigDir) || self.has(AppHome) {
    roles.push(Global)
  }
  guard !roles.is_empty() else { return [] }
  let platform = if options.isolated { None } else { context.platform }
  guard platform is Some(platform) else {
    if !options.isolated {
      notes.push(
        note(
          self,
          "discovery has no platform, so it skips the system and global user directories",
        ),
      )
    }
    return roles.map(role => {
      {
        source: @config.ConfigSource::skipped(File(role), name=self.display),
        candidates: [],
      }
    })
  }
  let vars : DirVars = {
    conventions: self,
    platform,
    env_vars: context.env_vars,
    working_dir: context.working_dir,
    notes,
  }
  let sources = []
  for role in roles {
    let paths = match role {
      System => self.files_in(self.system_path(vars), extensions)
      _ => self.global_candidates(vars, extensions)
    }
    sources.push({
      source: @config.ConfigSource::candidates(
        texts(paths),
        display=self.display,
        role~,
        name=self.display,
      ),
      candidates: paths,
    })
  }
  sources
}

///|
/// The inputs that give the system and global directories: the convention
/// set, the platform, the variable set of the run, the working directory for a
/// relative value, and the warnings of the run.
priv struct DirVars {
  conventions : Conventions
  platform : @config.Platform
  env_vars : Map[String, String]
  working_dir : @config.FileTreePath?
  notes : Array[@config.ConfigWarning]
}

///|
/// The system directory of the application.
fn Conventions::system_path(
  self : Conventions,
  vars : DirVars,
) -> @config.FileTreePath raise @config.ConfigError {
  let root = match vars.platform {
    Windows =>
      match vars.dir("PROGRAMDATA") {
        Some(dir) => dir
        None => @config.FileTreePath::parse("C:/ProgramData")
      }
    Linux | MacOs => @config.FileTreePath::parse("/etc")
  }
  root.child(self.name)
}

///|
/// The global candidates: `<app>/<app>.<ext>` in the user configuration
/// directory, then `<app>.<ext>` in the application home. They are
/// alternatives at one priority.
fn Conventions::global_candidates(
  self : Conventions,
  vars : DirVars,
  extensions : Array[String],
) -> Array[@config.FileTreePath] raise @config.ConfigError {
  let paths = []
  if self.has(UserConfigDir) && user_config_root(vars) is Some(root) {
    paths.append(self.files_in(root.child(self.name), extensions))
  }
  if self.has(AppHome) && self.home_path(vars) is Some(home) {
    paths.append(self.files_in(home, extensions))
  }
  paths
}

///|
/// The global user configuration directory, or `None` when the variables
/// that give it are not set.
fn user_config_root(
  vars : DirVars,
) -> @config.FileTreePath? raise @config.ConfigError {
  match vars.platform {
    Windows => vars.dir("APPDATA")
    Linux | MacOs => {
      // A relative XDG_CONFIG_HOME is invalid, so it falls back to the default.
      if vars.path("XDG_CONFIG_HOME") is Some(xdg) && xdg.is_absolute() {
        return Some(normalize(xdg))
      }
      match (vars.dir("HOME"), vars.platform) {
        (Some(home), MacOs) => Some(home.join("Library/Application Support"))
        (Some(home), _) => Some(home.child(".config"))
        (None, _) => None
      }
    }
  }
}

///|
/// The application home: `$<PREFIX>_HOME`, else `.<app>` in the user home.
fn Conventions::home_path(
  self : Conventions,
  vars : DirVars,
) -> @config.FileTreePath? raise @config.ConfigError {
  if vars.dir("\{self.prefix}_HOME") is Some(home) {
    return Some(home)
  }
  let user_home = match vars.platform {
    Windows => vars.dir("USERPROFILE")
    Linux | MacOs => vars.dir("HOME")
  }
  match user_home {
    Some(home) => Some(home.child(".\{self.name}"))
    None => None
  }
}

///|
/// `<app>.<ext>` in `dir` for each searched extension.
fn Conventions::files_in(
  self : Conventions,
  dir : @config.FileTreePath,
  extensions : Array[String],
) -> Array[@config.FileTreePath] raise @config.ConfigError {
  extensions.map(extension => dir.child("\{self.name}.\{extension}"))
}

///|
/// The parsed path in the variable `name`, in the native form of the
/// platform, or `None` when it is not set or empty. A value that is not a
/// valid path, such as the drive-relative `C:x` on Windows, counts as not set
/// and gives a `Note` warning.
fn DirVars::path(self : DirVars, name : String) -> @config.FileTreePath? {
  guard self.env_vars.get(name) is Some(value) && !value.is_empty() else {
    return None
  }
  Some(@config.FileTreePath::from_native(value, self.platform)) catch {
    InvalidFilePath(rule~, ..) => {
      let warning = note(
        self.conventions,
        "discovery ignores the variable \{name}, because \{rule.describe()}",
      )
      if !self.notes.contains(warning) {
        self.notes.push(warning)
      }
      None
    }
    _ => None
  }
}

///|
/// The directory that the variable `name` gives. An absolute value is
/// normalized. A relative value joins the working directory, when the working
/// directory is absolute.
fn DirVars::dir(
  self : DirVars,
  name : String,
) -> @config.FileTreePath? raise @config.ConfigError {
  guard self.path(name) is Some(value) else { return None }
  if value.is_absolute() {
    return Some(normalize(value))
  }
  match self.working_dir {
    Some(dir) if dir.is_absolute() => Some(normalize(dir.resolve(value)))
    _ => Some(value)
  }
}
