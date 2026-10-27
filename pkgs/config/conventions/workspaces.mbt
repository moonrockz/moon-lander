///|
/// What a workspace configuration declares, read through its key paths.
priv struct Declaration {
  members : Array[String]
  exclude : Array[String]
  default_member : String?
}

///|
/// The workspace that encloses a project root: its primary file, whose root is
/// the workspace directory, and the parsed value of that file.
priv struct Enclosing {
  file : ProjectFile
  value : @config.ConfigValue
}

///|
/// Whether `name` matches the pattern segment `pattern`. `*` matches any run
/// of characters, also an empty one. Every other character matches itself.
fn segment_matches(pattern : String, name : String) -> Bool {
  let pattern : Array[Char] = pattern.iter().collect()
  let name : Array[Char] = name.iter().collect()
  let mut at_pattern = 0
  let mut at_name = 0
  let mut star : Int? = None
  let mut retry = 0
  while at_name < name.length() {
    if at_pattern < pattern.length() && pattern[at_pattern] == '*' {
      star = Some(at_pattern)
      at_pattern += 1
      retry = at_name
    } else if at_pattern < pattern.length() &&
      pattern[at_pattern] == name[at_name] {
      at_pattern += 1
      at_name += 1
    } else if star is Some(index) {
      // The last `*` takes one more character, and the match starts again.
      at_pattern = index + 1
      retry += 1
      at_name = retry
    } else {
      return false
    }
  }
  pattern[at_pattern:].iter().all(c => c == '*')
}

///|
/// Whether the path segments `path` match the pattern segments `pattern`. A
/// `**` segment matches zero or more whole segments.
fn segments_match(pattern : ArrayView[String], path : ArrayView[String]) -> Bool {
  match pattern {
    [] => path.is_empty()
    ["**", .. rest] => {
      for skipped = 0; skipped <= path.length(); skipped = skipped + 1 {
        if segments_match(rest, path[skipped:]) {
          return true
        }
      }
      false
    }
    [head, .. rest] =>
      match path {
        [name, .. tail] if segment_matches(head, name) =>
          segments_match(rest, tail)
        _ => false
      }
  }
}

///|
/// The segments of a workspace entry, without empty and `.` segments.
fn entry_segments(entry : String) -> Array[String] {
  entry
  .split("/")
  .filter(segment => !segment.is_empty() && segment != ".")
  .map(segment => segment.to_owned())
  .collect()
}

///|
/// Whether a workspace entry stays in the workspace directory: it does not
/// start with `/` or a drive such as `C:`, and it has no `\` and no `..`
/// segment. An empty entry and `.` name the workspace root.
fn is_confined(entry : String) -> Bool {
  let drive = entry.length() >= 2 &&
    entry.get_char(0) is Some(letter) &&
    letter.is_ascii_alphabetic() &&
    entry[1:2] == ":"
  !(entry.has_prefix("/") ||
  drive ||
  entry.contains("\\") ||
  entry.split("/").any(segment => segment == ".."))
}

///|
/// The segments of `dir` below `root`, or `None` when `dir` is not `root` or
/// below it.
fn relative_segments(root : String, dir : String) -> Array[String]? {
  guard is_within(dir, root) else { return None }
  Some(entry_segments(dir[root.length():].to_owned()))
}

///|
/// Whether one of `patterns` selects `dir`, relative to `root`.
fn patterns_select(
  root : String,
  patterns : Array[String],
  dir : String,
) -> Bool {
  guard relative_segments(root, dir) is Some(path) else { return false }
  patterns.iter().any(pattern => segments_match(entry_segments(pattern), path))
}

///|
/// Whether `dir`, which the member entries select, is a member of the
/// workspace at `root`: it is below `root`, it is not `root`, and no exclude
/// entry selects it.
fn is_member(root : String, exclude : Array[String], dir : String) -> Bool {
  relative_segments(root, dir) is Some(path) &&
  !path.is_empty() &&
  !patterns_select(root, exclude, dir)
}

///|
/// `root` joined with the segments of a confined entry.
fn entry_dir(root : String, entry : String) -> String {
  entry_segments(entry).fold(init=root, join)
}

///|
/// The confined entries of `entries`, with a `Note` warning for each other
/// entry.
fn Scan::confined(self : Scan, entries : Array[String]) -> Array[String] {
  entries.filter(entry => {
    let confined = is_confined(entry)
    if !confined {
      self.warn(
        "discovery skips the workspace entry \{entry}, because it is not in the workspace directory",
      )
    }
    confined
  })
}

///|
/// The workspace declaration in `value`, or `None` when the value sets neither
/// the members nor the default member.
fn Conventions::declaration(
  self : Conventions,
  value : @config.ConfigValue,
) -> Declaration? raise @config.ConfigError {
  guard self.workspace is Some(keys) else { return None }
  let config = @config.build([@config.in_memory(value, name=self.display)])
  let members : Array[String]? = optional(config, keys.members)
  let default_member : String? = optional(config, keys.default_member)
  guard members is Some(_) || default_member is Some(_) else { return None }
  let exclude : Array[String]? = optional(config, keys.exclude)
  Some({
    members: members.unwrap_or([]),
    exclude: exclude.unwrap_or([]),
    default_member,
  })
}

///|
/// The value at `key` decoded into a `T`, or `None` when no source sets it.
fn[T : FromJson] optional(
  config : @config.Config,
  key : String,
) -> T? raise @config.ConfigError {
  guard config.get(@config.KeyPath::parse(key)) is Some(_) else { return None }
  Some(@config.bind(config, key))
}

///|
/// The project name in `value`, or `None` when it sets none.
fn Conventions::project_name(
  self : Conventions,
  value : @config.ConfigValue,
) -> String? raise @config.ConfigError {
  guard self.workspace is Some(keys) else { return None }
  let config = @config.build([@config.in_memory(value, name=self.display)])
  optional(config, keys.project_name)
}

///|
/// The members of the workspace at `root`, in entry order, each one time. A
/// literal entry gives its directory whether or not it exists. A wildcard
/// entry gives the directories that hold a primary or legacy candidate, in
/// path order. No member is excluded or the root. `None` when the tree does
/// not hold a listing yet.
fn Scan::members(
  self : Scan,
  root : String,
  declaration : Declaration,
) -> Array[String]? {
  let members = []
  let exclude = self.confined(declaration.exclude)
  let mut known = true
  for entry in self.confined(declaration.members) {
    let dirs = if entry.contains("*") {
      guard self.expand(root, entry_segments(entry)) is Some(dirs) else {
        known = false
        continue
      }
      dirs.sort()
      dirs
    } else {
      [entry_dir(root, entry)]
    }
    for dir in dirs {
      if !members.contains(dir) && is_member(root, exclude, dir) {
        members.push(dir)
      }
    }
  }
  if known {
    Some(members)
  } else {
    None
  }
}

///|
/// The directories below `dir` that the pattern segments `segments` select
/// and that hold a primary or legacy candidate. A wildcard never enters a
/// hidden directory. `None` when the tree does not hold a listing yet.
fn Scan::expand(
  self : Scan,
  dir : String,
  segments : ArrayView[String],
) -> Array[String]? {
  match segments {
    [] =>
      match self.config_at(dir) {
        NotKnown => None
        NoFile => Some([])
        OneFile(_) | LegacyAt(_) | Several => Some([dir])
      }
    [head, .. rest] => {
      guard self.children(dir) is Some(children) else { return None }
      let found = []
      let mut known = true
      let parts : Array[(String, ArrayView[String])] = if head == "**" {
        [(dir, rest), ..children.map(child => (child, segments))]
      } else {
        children
        .filter(child => segment_matches(head, file_name(child)))
        .map(child => (child, rest))
      }
      for part in parts {
        let (path, next) = part
        match self.expand(path, next) {
          Some(dirs) => found.append(dirs)
          None => known = false
        }
      }
      if known {
        Some(found)
      } else {
        None
      }
    }
  }
}

///|
/// The directories in `dir` whose names do not start with `.`, or `None` when
/// the tree does not hold the listing yet. An `Inaccessible` entry can be a
/// directory, so it is in the result: a pattern that selects it asks for its
/// listing, and the host reports the error.
fn Scan::children(self : Scan, dir : String) -> Array[String]? {
  match self.context.tree.listing(dir) {
    Found(entries) =>
      Some(
        entries
        .filter(entry => {
          entry.kind is (Directory | Inaccessible) && !entry.name.has_prefix(".")
        })
        .map(entry => join(dir, entry.name)),
      )
    Missing => Some([])
    Unknown => {
      add_need(self.needs, ListDir(dir))
      None
    }
  }
}

///|
/// Whether the workspace at `root` with `declaration` selects `dir` as a
/// member.
fn Scan::selects(
  self : Scan,
  root : String,
  declaration : Declaration,
  dir : String,
) -> Bool {
  patterns_select(root, self.confined(declaration.members), dir) &&
  is_member(root, self.confined(declaration.exclude), dir)
}

///|
/// The nearest workspace above the project root `root`, up to the boundary
/// `stop`, whose members select `root`. The search passes over a directory
/// with no file, more than one file, a file that does not parse, and a file
/// that is not a workspace or does not select `root`. `Some(None)` when no
/// workspace selects `root`, and `None` when the tree does not hold an entry
/// yet. One directory is examined in each round, nearest first.
fn Scan::enclosing(
  self : Scan,
  root : String,
  stop : String?,
) -> Enclosing?? {
  let mut dir = root
  while true {
    let below_stop = match stop {
      Some(stop) => dir != stop && is_within(dir, stop)
      None => true
    }
    guard below_stop && parent_dir(dir) is Some(parent) else { break }
    dir = parent
    let file = match self.config_at(dir) {
      NotKnown => return None
      NoFile | Several => continue
      OneFile(path) => { path, root: dir, kind: Discovered }
      LegacyAt(path) => { path, root: dir, kind: LegacyFile }
    }
    // A file that does not parse, or is not a workspace, is passed over.
    let value = try self.value_of(file) catch {
      _ => continue
    } noraise {
      Found(value) => value
      Unknown => return None
      Missing => continue
    }
    let declaration = try self.conventions.declaration(value) catch {
      _ => continue
    } noraise {
      Some(declaration) => declaration
      None => continue
    }
    if self.selects(dir, declaration, root) {
      return Some(Some({ file, value }))
    }
  }
  Some(None)
}

///|
/// The value that gives the workspace keys: the system file, then the global
/// user file, then `primary`, merged. A machine source that finds no file, or
/// more than one, adds nothing; the core load reports it. `None` when the
/// tree does not hold an entry yet.
fn Scan::root_value(
  self : Scan,
  machine : Array[MachineSource],
  primary : @config.ConfigValue,
) -> @config.ConfigValue? raise @config.ConfigError {
  let mut value = @config.fields([])
  let mut known = true
  for source in machine {
    let existing = []
    for candidate in source.candidates {
      match self.context.tree.is_file(candidate) {
        Found(true) => existing.push(candidate)
        Found(false) | Missing => ()
        Unknown => {
          add_need(self.needs, self.context.tree.file_request(candidate))
          known = false
        }
      }
    }
    guard known && existing is [path] else { continue }
    match self.value_of({ path, root: parent_of(path), kind: Discovered }) {
      Found(layer) => value = @config.merge(value, layer, source=path)
      Missing => ()
      Unknown => known = false
    }
  }
  if known {
    Some(@config.merge(value, primary))
  } else {
    None
  }
}

///|
/// The member that automatic selection gives: the member that holds the
/// start directory, then the default member, then the only member.
/// `Some(None)` when no member is selected, and `None` when the tree does not
/// hold an entry yet. A default member that is not confined gives a warning
/// and no member.
fn Scan::automatic_member(
  self : Scan,
  root : String,
  declaration : Declaration,
  start : String?,
) -> String?? {
  guard self.members(root, declaration) is Some(members) else { return None }
  if start is Some(start) &&
    members.iter().find_first(dir => is_within(start, dir))
    is Some(dir) {
    return Some(Some(dir))
  }
  if declaration.default_member is Some(entry) {
    guard self.confined([entry]) is [_] else { return Some(None) }
    let dir = entry_dir(root, entry)
    return Some(
      if is_member(root, self.confined(declaration.exclude), dir) {
        Some(dir)
      } else {
        None
      },
    )
  }
  Some(if members is [only] { Some(only) } else { None })
}

///|
/// The project that the selector `selector` names in the workspace at
/// `root`: `.` names the root, then a member path relative to `root`, then
/// the project name of the root value or of a member primary. `Some(None)`
/// names the root project, and `None` means that the tree does not hold an
/// entry yet. No match raises `UnknownProject`, and more than one name match
/// raises `AmbiguousProject`.
fn Scan::selected_project(
  self : Scan,
  root : String,
  declaration : Declaration?,
  value : @config.ConfigValue,
  selector : String,
) -> String?? raise @config.ConfigError {
  let wanted = entry_segments(selector.replace_all(old="\\", new="/"))
  if wanted.is_empty() {
    return Some(None)
  }
  let members = match declaration {
    Some(declaration) =>
      match self.members(root, declaration) {
        Some(members) => members
        None => return None
      }
    None => []
  }
  for dir in members {
    if relative_segments(root, dir) == Some(wanted) {
      return Some(Some(dir))
    }
  }
  let matches : Array[String?] = []
  if self.conventions.project_name(value) == Some(selector) {
    matches.push(None)
  }
  let mut known = true
  for dir in members {
    let file = match self.config_at(dir) {
      NotKnown => {
        known = false
        continue
      }
      NoFile | Several => continue
      OneFile(path) => { path, root: dir, kind: Discovered }
      LegacyAt(path) => { path, root: dir, kind: LegacyFile }
    }
    match self.value_of(file) {
      Found(value) =>
        if self.conventions.project_name(value) == Some(selector) {
          matches.push(Some(dir))
        }
      Missing => ()
      Unknown => known = false
    }
  }
  guard known else { return None }
  match matches {
    [only] => Some(only)
    [] => raise UnknownProject(selector~, workspace=root)
    _ =>
      raise AmbiguousProject(
        selector~,
        matches=matches.map(found => match found {
          Some(dir) =>
            relative_segments(root, dir).unwrap_or([]).join("/")
          None => "."
        }),
      )
  }
}

///|
/// The last name of `path`.
fn file_name(path : String) -> String {
  match path.rev_find("/") {
    Some(index) => path[index + 1:].to_owned()
    None => path
  }
}
