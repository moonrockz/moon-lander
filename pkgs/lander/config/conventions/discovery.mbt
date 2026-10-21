///|
/// Find the project primary. Walk up from the working directory and stop at
/// the first directory that holds a primary candidate as a file. The candidate
/// list at that directory becomes one file source, so the core load reads it,
/// or raises `Ambiguous` when more than one candidate exists. With no primary,
/// the candidate list at the start directory reports `NotFound`.
fn discover(
  conventions : Conventions,
  context : @config.LoadContext,
) -> @config.LoadStep[@config.Expansion] {
  guard context.working_dir is Some(working_dir) else {
    return Done({
      sources: [
        @config.ConfigSource::skipped(
          File(Workspace),
          name=conventions.display,
        ),
      ],
      warnings: [
        Note(
          source=conventions.display,
          message="discovery has no working directory to start from",
        ),
      ],
    })
  }
  let extensions = searched_extensions(context.formats)
  let start = trim_dir(working_dir)
  let mut dir = start
  while true {
    let candidates = conventions.candidates(dir, extensions)
    let mut found = false
    for candidate in candidates {
      match context.tree.is_file(candidate) {
        Found(true) => found = true
        Found(false) | Missing => ()
        Unknown => return Need([ListDir(dir)])
      }
    }
    if found {
      return Done({ sources: [conventions.primary(candidates)], warnings: [] })
    }
    guard conventions.walk_up && parent_dir(dir) is Some(parent) else { break }
    dir = parent
  }
  Done({
    sources: [conventions.primary(conventions.candidates(start, extensions))],
    warnings: [],
  })
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
    match layout {
      Root =>
        for extension in extensions {
          paths.push(join(dir, "\{self.name}.\{extension}"))
        }
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
/// Whether `dir` is a root: `/`, a drive such as `C:/`, or a UNC share such as
/// `//server/share`.
fn is_root(dir : String) -> Bool {
  dir == "/" ||
  (dir.length() == 3 && dir[1:3] == ":/") ||
  (dir.has_prefix("//") && dir[2:].split("/").count() <= 2)
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
fn join(dir : String, name : String) -> String {
  if dir.has_suffix("/") {
    dir + name
  } else {
    "\{dir}/\{name}"
  }
}
