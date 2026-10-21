///|
/// Find the project primary. Walk up from the working directory to the
/// boundary, or to the file-system root, and stop at the first directory that
/// holds a primary candidate or the legacy file. The candidate list at that
/// directory becomes one file source, so the core load reads it, or raises
/// `Ambiguous` when more than one candidate exists. A legacy file counts only
/// when no primary exists there. With no root, the candidate list at the start
/// directory reports `NotFound`.
fn discover(
  conventions : Conventions,
  options : DiscoveryOptions,
  context : @config.LoadContext,
) -> @config.LoadStep[@config.Expansion] raise @config.ConfigError {
  let notes = unread_options(conventions, options)
  guard context.working_dir is Some(working_dir) else {
    return skipped(
      conventions,
      [..notes, note(conventions, "discovery has no working directory to start from")],
    )
  }
  // The core joins a relative candidate to the working directory again, and a
  // relative directory has no parents to walk to.
  guard is_absolute(working_dir) else {
    return skipped(conventions, [
      ..notes,
      note(
        conventions,
        "discovery needs an absolute working directory, not \{working_dir}",
      ),
    ])
  }
  let start = normalize(working_dir)
  let stop = conventions.boundary.map(dir => {
    normalize(if is_absolute(dir) { dir } else { join(start, dir) })
  })
  if stop is Some(stop) && !is_within(start, stop) {
    raise OutsideBoundary(start~, boundary=stop)
  }
  let extensions = searched_extensions(context.formats)
  let mut dir = start
  while true {
    let candidates = conventions.candidates(dir, extensions)
    let needs : Array[@config.FileRequest] = []
    let mut found = false
    for candidate in candidates {
      match context.tree.is_file(candidate) {
        Found(true) => found = true
        Found(false) | Missing => ()
        Unknown => add_need(needs, ListDir(parent_of(candidate)))
      }
    }
    // The core load checks the other candidates and raises `Ambiguous`.
    if found {
      return Done({ sources: [conventions.primary(candidates)], warnings: notes })
    }
    if conventions.legacy is Some(legacy) {
      let path = join(dir, legacy.name)
      match context.tree.is_file(path) {
        Found(true) if needs.is_empty() =>
          return legacy_source(conventions, legacy, path, context, notes)
        Unknown => add_need(needs, ListDir(dir))
        _ => ()
      }
    }
    if !needs.is_empty() {
      return Need(needs)
    }
    guard conventions.walk_up &&
      stop != Some(dir) &&
      parent_dir(dir) is Some(parent) else {
      break
    }
    dir = parent
  }
  Done({
    sources: [conventions.primary(conventions.candidates(start, extensions))],
    warnings: notes,
  })
}

///|
/// The legacy file at `path` as a `Legacy` file source, once the tree holds
/// its text.
fn legacy_source(
  conventions : Conventions,
  legacy : Legacy,
  path : String,
  context : @config.LoadContext,
  notes : Array[@config.ConfigWarning],
) -> @config.LoadStep[@config.Expansion] raise @config.ConfigError {
  match context.tree.file(path) {
    Found(text) => {
      let value = (legacy.decode)((legacy.format.parse)(text, path))
      Done({
        sources: [
          @config.ConfigSource::parsed_file(
            path,
            value,
            role=Legacy,
            name=conventions.display,
          ),
        ],
        warnings: notes,
      })
    }
    Missing => raise FileNotFound(path~)
    Unknown => Need([ReadFile(path)])
  }
}

///|
/// A skipped project source with `warnings`.
fn skipped(
  conventions : Conventions,
  warnings : Array[@config.ConfigWarning],
) -> @config.LoadStep[@config.Expansion] {
  Done({
    sources: [
      @config.ConfigSource::skipped(File(Workspace), name=conventions.display),
    ],
    warnings,
  })
}

///|
fn note(conventions : Conventions, message : String) -> @config.ConfigWarning {
  Note(source=conventions.display, message~)
}

///|
/// A note for each given option that discovery does not read yet.
fn unread_options(
  conventions : Conventions,
  options : DiscoveryOptions,
) -> Array[@config.ConfigWarning] {
  let notes = []
  if options.environment is Some(_) {
    notes.push(note(conventions, "discovery does not read the environment option yet"))
  }
  if !(options.config is Discover) {
    notes.push(note(conventions, "discovery does not read the config option yet"))
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
  let paths = []
  for layout in self.layouts {
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
