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
) -> Array[@config.ConfigSource] {
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
      @config.ConfigSource::skipped(File(role), name=self.display)
    })
  }
  let vars : DirVars = { platform, env_vars: context.env_vars, working_dir: context.working_dir }
  roles.map(role => {
    let paths = match role {
      System => self.files_in(self.system_path(vars), extensions)
      _ => self.global_candidates(vars, extensions)
    }
    @config.ConfigSource::candidates(
      paths,
      display=self.display,
      role~,
      name=self.display,
    )
  })
}

///|
/// The inputs that give the system and global directories: the platform, the
/// variable set of the run, and the working directory for a relative value.
priv struct DirVars {
  platform : @config.Platform
  env_vars : Map[String, String]
  working_dir : String?
}

///|
/// The system directory of the application.
fn Conventions::system_path(self : Conventions, vars : DirVars) -> String {
  let root = match vars.platform {
    Windows => vars.dir("PROGRAMDATA").unwrap_or("C:/ProgramData")
    Linux | MacOs => "/etc"
  }
  join(root, self.name)
}

///|
/// The global candidates: `<app>/<app>.<ext>` in the user configuration
/// directory, then `<app>.<ext>` in the application home. They are
/// alternatives at one priority.
fn Conventions::global_candidates(
  self : Conventions,
  vars : DirVars,
  extensions : Array[String],
) -> Array[String] {
  let paths = []
  if self.has(UserConfigDir) && user_config_root(vars) is Some(root) {
    paths.append(self.files_in(join(root, self.name), extensions))
  }
  if self.has(AppHome) && self.home_path(vars) is Some(home) {
    paths.append(self.files_in(home, extensions))
  }
  paths
}

///|
/// The global user configuration directory, or `None` when the variables
/// that give it are not set.
fn user_config_root(vars : DirVars) -> String? {
  match vars.platform {
    Windows => vars.dir("APPDATA")
    Linux | MacOs => {
      // A relative XDG_CONFIG_HOME is invalid, so it falls back to the default.
      if vars.value("XDG_CONFIG_HOME") is Some(xdg) &&
        is_absolute_on(xdg, vars.platform) {
        return Some(normalize(xdg))
      }
      let home = vars.dir("HOME")
      match vars.platform {
        MacOs => home.map(home => join(home, "Library/Application Support"))
        _ => home.map(home => join(home, ".config"))
      }
    }
  }
}

///|
/// The application home: `$<PREFIX>_HOME`, else `.<app>` in the user home.
fn Conventions::home_path(self : Conventions, vars : DirVars) -> String? {
  if vars.dir("\{self.prefix}_HOME") is Some(home) {
    return Some(home)
  }
  let user_home = match vars.platform {
    Windows => vars.dir("USERPROFILE")
    Linux | MacOs => vars.dir("HOME")
  }
  user_home.map(home => join(home, ".\{self.name}"))
}

///|
/// `<app>.<ext>` in `dir` for each searched extension.
fn Conventions::files_in(
  self : Conventions,
  dir : String,
  extensions : Array[String],
) -> Array[String] {
  extensions.map(extension => join(dir, "\{self.name}.\{extension}"))
}

///|
/// The value of the variable `name` in the `/` form, or `None` when it is not
/// set or empty. On Windows, `\` becomes `/`.
fn DirVars::value(self : DirVars, name : String) -> String? {
  guard self.env_vars.get(name) is Some(value) && !value.is_empty() else {
    return None
  }
  match self.platform {
    Windows => Some(value.replace_all(old="\\", new="/"))
    Linux | MacOs => Some(value)
  }
}

///|
/// The directory that the variable `name` gives. An absolute value is
/// normalized. A relative value joins the working directory, when the working
/// directory is absolute.
fn DirVars::dir(self : DirVars, name : String) -> String? {
  guard self.value(name) is Some(value) else { return None }
  if is_absolute_on(value, self.platform) {
    return Some(normalize(value))
  }
  match self.working_dir {
    Some(dir) if is_absolute(dir) => Some(normalize(join(dir, value)))
    _ => Some(value)
  }
}

///|
/// Whether `path`, in the `/` form, is absolute on `platform`. On Windows that
/// is a drive letter followed by `/` (`C:/`) or a UNC prefix (`//server`); a
/// drive-relative path such as `C:foo` is not absolute. Elsewhere the path
/// starts with `/`.
fn is_absolute_on(path : String, platform : @config.Platform) -> Bool {
  match platform {
    Windows =>
      path.has_prefix("//") ||
      (path.length() >= 3 && path.get_char(0) is Some(letter) &&
      letter.is_ascii_alphabetic() &&
      path[1:3] == ":/")
    Linux | MacOs => path.has_prefix("/")
  }
}
