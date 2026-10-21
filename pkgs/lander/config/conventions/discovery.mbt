///|
/// Give the sources of the convention set in merge order: the system and
/// global user sources, then the project primary and its overrides.
fn discover(
  conventions : Conventions,
  options : DiscoveryOptions,
  context : @config.LoadContext,
) -> @config.LoadStep[@config.Expansion] raise @config.ConfigError {
  let notes = unread_options(conventions, options)
  let environment = environment_name(conventions, options~, context.env_vars)
  let extensions = searched_extensions(context.formats)
  let machine = conventions.machine_sources(options, context, extensions, notes)
  let inputs = { options, environment, extensions }
  match conventions.project_sources(inputs, context, notes) {
    Need(requests) => Need(requests)
    Done(project) => Done({ sources: [..machine, ..project], warnings: notes })
  }
}

///|
/// The inputs of the project-tier sources: the discovery options, the
/// environment name of the run, and the searched extensions.
priv struct ProjectInputs {
  options : DiscoveryOptions
  environment : String?
  extensions : Array[String]
}

///|
/// The project primary, its environment file, and its overrides.
/// `Explicit(path)` gives the primary with no walk-up, and `Skip` skips it.
/// Otherwise walk up from the working directory to the boundary, or to the
/// file-system root, and stop at the first directory that holds a primary
/// candidate or the legacy file. The candidate list at that directory becomes
/// one file source, so the core load reads it, or raises `Ambiguous` when more
/// than one candidate exists. A legacy file counts only when no primary exists
/// there. With no root, the candidate list at the start directory reports
/// `NotFound`.
fn Conventions::project_sources(
  self : Conventions,
  project : ProjectInputs,
  context : @config.LoadContext,
  notes : Array[@config.ConfigWarning],
) -> @config.LoadStep[Array[@config.ConfigSource]] raise @config.ConfigError {
  let extensions = project.extensions
  match project.options.config {
    Explicit(path) => return Done(self.explicit_sources(path, project, context))
    Skip => return Done([self.skipped_project()])
    Discover => ()
  }
  guard context.working_dir is Some(working_dir) else {
    notes.push(note(self, "discovery has no working directory to start from"))
    return Done([self.skipped_project()])
  }
  // The core joins a relative candidate to the working directory again, and a
  // relative directory has no parents to walk to.
  guard is_absolute(working_dir) else {
    notes.push(
      note(
        self,
        "discovery needs an absolute working directory, not \{working_dir}",
      ),
    )
    return Done([self.skipped_project()])
  }
  let start = normalize(working_dir)
  let stop = self.boundary.map(dir => {
    normalize(if is_absolute(dir) { dir } else { join(start, dir) })
  })
  if stop is Some(stop) && !is_within(start, stop) {
    raise OutsideBoundary(start~, boundary=stop)
  }
  let mut dir = start
  while true {
    let candidates = self.candidates(dir, extensions)
    let needs : Array[@config.FileRequest] = []
    let mut found : String? = None
    for candidate in candidates {
      match context.tree.is_file(candidate) {
        Found(true) => if found is None { found = Some(candidate) }
        Found(false) | Missing => ()
        Unknown => add_need(needs, ListDir(parent_of(candidate)))
      }
    }
    // The core load checks the other candidates and raises `Ambiguous`.
    if found is Some(primary) {
      return Done([
        self.primary(candidates),
        ..self.overrides(primary, project),
      ])
    }
    if self.legacy is Some(legacy) {
      let path = join(dir, legacy.name)
      match context.tree.is_file(path) {
        Found(true) if needs.is_empty() =>
          return legacy_source(self, legacy, path, context)
        Unknown => add_need(needs, ListDir(dir))
        _ => ()
      }
    }
    if !needs.is_empty() {
      return Need(needs)
    }
    guard self.walk_up && stop != Some(dir) && parent_dir(dir) is Some(parent) else {
      break
    }
    dir = parent
  }
  Done([self.primary(self.candidates(start, extensions))])
}

///|
/// The explicit primary at `path` with the role `Explicit`, and its
/// environment file and overrides when the path has a standard layout. A
/// relative path joins the working directory. On Windows, `\` becomes `/`.
fn Conventions::explicit_sources(
  self : Conventions,
  given : String,
  project : ProjectInputs,
  context : @config.LoadContext,
) -> Array[@config.ConfigSource] {
  let path = match context.platform {
    Some(Windows) => given.replace_all(old="\\", new="/")
    _ => given
  }
  let resolved = if is_absolute(path) {
    normalize(path)
  } else {
    match context.working_dir {
      Some(dir) if is_absolute(dir) => normalize(join(dir, path))
      _ => path
    }
  }
  [
    @config.ConfigSource::file(resolved, role=Explicit, name=self.display),
    ..self.overrides(resolved, project),
  ]
}

///|
/// The environment file, local override and user override sources next to the
/// primary at `path`, or none when the path has no standard layout. In
/// isolated mode the overrides report `Skipped`; the environment file stays.
fn Conventions::overrides(
  self : Conventions,
  path : String,
  project : ProjectInputs,
) -> Array[@config.ConfigSource] {
  let { options, environment, extensions } = project
  guard self.adjacent(path, extensions) is Some((dir, stem)) else { return [] }
  let sources = []
  if environment is Some(name) {
    sources.push(self.environment_file(dir, stem, name, extensions))
  }
  let kinds : Array[(Part, @config.FileRole, String)] = [
    (LocalOverrides, LocalOverride, "local"),
    (UserOverrides, UserOverride, "user"),
  ]
  for kind in kinds {
    let (part, role, word) = kind
    guard self.has(part) else { continue }
    sources.push(
      if options.isolated {
        @config.ConfigSource::skipped(File(role), name=self.display)
      } else {
        @config.ConfigSource::candidates(
          extensions.map(extension => join(dir, "\{stem}.\{word}.\{extension}")),
          display=self.display,
          role~,
          name=self.display,
        )
      },
    )
  }
  sources
}

///|
/// The directory and the file stem of the primary at `path` when the path has
/// a standard layout: `<app>` for `<app>.<ext>` (also `.<app>/<app>.<ext>`),
/// and `config` for `.config/<app>/config.<ext>`.
fn Conventions::adjacent(
  self : Conventions,
  path : String,
  extensions : Array[String],
) -> (String, String)? {
  let dir = parent_of(path)
  let file = match path.rev_find("/") {
    Some(index) => path[index + 1:].to_owned()
    None => path
  }
  for extension in extensions {
    if file == "\{self.name}.\{extension}" {
      return Some((dir, self.name))
    }
    if file == "config.\{extension}" &&
      (dir == ".config/\{self.name}" ||
      dir.has_suffix("/.config/\{self.name}")) {
      return Some((dir, "config"))
    }
  }
  None
}

///|
/// The legacy file at `path` as a `Legacy` file source, once the tree holds
/// its text. A legacy file has no overrides.
fn legacy_source(
  conventions : Conventions,
  legacy : Legacy,
  path : String,
  context : @config.LoadContext,
) -> @config.LoadStep[Array[@config.ConfigSource]] raise @config.ConfigError {
  match context.tree.file(path) {
    Found(text) => {
      let value = (legacy.decode)((legacy.format.parse)(text, path))
      Done([
        @config.ConfigSource::parsed_file(
          path,
          value,
          role=Legacy,
          name=conventions.display,
        ),
      ])
    }
    Missing => raise FileNotFound(path~)
    Unknown => Need([ReadFile(path)])
  }
}

///|
/// A skipped project source.
fn Conventions::skipped_project(self : Conventions) -> @config.ConfigSource {
  @config.ConfigSource::skipped(File(Workspace), name=self.display)
}

///|
fn note(conventions : Conventions, message : String) -> @config.ConfigWarning {
  Note(source=conventions.display, message~)
}

///|
/// A note for each given option that discovery does not read: the environment
/// with environments off, and the project, which it does not read yet.
fn unread_options(
  conventions : Conventions,
  options : DiscoveryOptions,
) -> Array[@config.ConfigWarning] {
  let notes = []
  if options.environment is Some(_) && conventions.environments is None {
    notes.push(
      note(
        conventions, "environments are off, so discovery ignores the environment option",
      ),
    )
  }
  if options.project is Some(_) {
    notes.push(note(conventions, "discovery does not read the project option yet"))
  }
  notes
}

///|
/// The primary candidates in `dir`, layout by layout, in extension order.
fn Conventions::candidates(
  self : Conventions,
  dir : String,
  extensions : Array[String],
) -> Array[String] {
  guard self.has(Layouts) else { return [] }
  let layouts : Array[Layout] = [Root, Hidden, DotConfig]
  let paths = []
  for layout in layouts {
    for extension in extensions {
      let relative = match layout {
        Root => "\{self.name}.\{extension}"
        Hidden => ".\{self.name}/\{self.name}.\{extension}"
        DotConfig => ".config/\{self.name}/config.\{extension}"
      }
      paths.push(join(dir, relative))
    }
  }
  paths
}

///|
fn Conventions::primary(
  self : Conventions,
  candidates : Array[String],
) -> @config.ConfigSource {
  @config.ConfigSource::candidates(
    candidates,
    display=self.display,
    role=Workspace,
  )
}

///|
fn add_need(needs : Array[@config.FileRequest], request : @config.FileRequest) -> Unit {
  if !needs.contains(request) {
    needs.push(request)
  }
}

///|
/// The extensions of the registered formats, in registration order, each one
/// time.
fn searched_extensions(formats : Array[@config.Format]) -> Array[String] {
  let extensions = []
  for format in formats {
    for extension in format.extensions {
      if !extensions.contains(extension) {
        extensions.push(extension)
      }
    }
  }
  extensions
}

///|
/// Whether `path` is absolute: it starts with `/` (also `//server/share`) or
/// with a drive such as `C:/`.
fn is_absolute(path : String) -> Bool {
  path.has_prefix("/") || (path.length() >= 3 && path[1:3] == ":/")
}

///|
/// Whether `dir` is `root` or below it.
fn is_within(dir : String, root : String) -> Bool {
  dir == root ||
  dir.has_prefix(if root.has_suffix("/") { root } else { root + "/" })
}

///|
/// Whether `dir` is a root: `/`, a drive such as `C:/`, or a UNC share such as
/// `//server/share`.
fn is_root(dir : String) -> Bool {
  dir == "/" ||
  (dir.length() == 3 && dir[1:3] == ":/") ||
  (dir.has_prefix("//") && dir[2:].split("/").count() <= 2)
}

///|
/// The absolute `path` without `.` segments, with each `..` segment applied,
/// and without a trailing `/` except at a root. `..` never goes above the root.
fn normalize(path : String) -> String {
  let (root, rest) = split_root(path)
  let names : Array[String] = []
  for name in rest.split("/") {
    match name {
      "" | "." => ()
      ".." => names.pop() |> ignore
      _ => names.push(name.to_owned())
    }
  }
  if names.is_empty() {
    trim_dir(root)
  } else {
    root + names.join("/")
  }
}

///|
/// The root of the absolute `path` (`/`, `C:/`, or `//server/share/`) and the
/// rest.
fn split_root(path : String) -> (String, String) {
  if path.has_prefix("//") {
    let parts = path[2:].split("/").map(part => part.to_owned()).collect()
    let share = parts.length().min(2)
    let root = "//" + parts[:share].join("/") + "/"
    return (root, parts[share:].join("/"))
  }
  if path.length() >= 3 && path[1:3] == ":/" {
    return (path[:3].to_owned(), path[3:].to_owned())
  }
  ("/", path[1:].to_owned())
}

///|
/// `dir` without a trailing `/`, except at a root.
fn trim_dir(dir : String) -> String {
  if dir.length() > 1 && dir.has_suffix("/") && !is_root(dir) {
    dir[:dir.length() - 1].to_owned()
  } else {
    dir
  }
}

///|
/// The directory above `dir`, or `None` at a root or for a path with no `/`.
fn parent_dir(dir : String) -> String? {
  if is_root(dir) {
    return None
  }
  match dir.rev_find("/") {
    None => None
    Some(0) => Some("/")
    Some(index) => {
      let parent = dir[:index].to_owned()
      if parent.length() == 2 && parent[1:2] == ":" {
        Some(parent + "/")
      } else {
        Some(parent)
      }
    }
  }
}

///|
/// The directory of the file `path`.
fn parent_of(path : String) -> String {
  parent_dir(path).unwrap_or(".")
}

///|
fn join(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    "\{dir}/\{name}"
  }
}
