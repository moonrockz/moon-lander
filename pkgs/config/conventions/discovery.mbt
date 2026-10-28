///|
/// Give the sources of the convention set in merge order: the system and
/// global user sources, then the project tier. When a member is selected, the
/// inherited filter applies to the system and global user sources.
fn discover(
  conventions : Conventions,
  options : DiscoveryOptions,
  context : @config.LoadContext,
) -> @config.LoadStep[@config.Expansion] raise @config.ConfigError {
  conventions.check_formats(context.formats)
  let notes = unread_options(conventions, options)
  let environment = environment_name(conventions, options~, context.env_vars)
  let extensions = searched_extensions(context.formats)
  let scan = Scan::new(conventions, context, extensions, notes)
  let machine = scan.machine_sources(options)
  if !scan.needs.is_empty() { return Need(scan.needs) }
  let inputs = { options, environment, extensions }
  match conventions.project_sources(inputs, scan, machine) {
    Need(requests) => Need(requests)
    Done(tier) => {
      let inherited = if tier.has_member {
        key_paths(conventions.inherited)
      } else {
        []
      }
      let sources = machine.map(machine_source => {
        filtered(machine_source.source, inherited, warn=false)
      })
      let resolution = match conventions.profiles {
        None => None
        Some(policy) => {
          let variable_name = "\{conventions.prefix}_PROFILES"
          let variable = context.env_vars.get(variable_name).map(text => (variable_name, text))
          let input = @profiles.SelectionInput::new(options.profiles, variable?)
          if conventions.layers is Some(_) {
            let layers = @profiles.ControlLayers::new(if input.disabled() { [] } else { tier.controls })
            Some(@profiles.resolve_layers(policy, input, layers))
          } else {
          let mut controls : (@config.ConfigValue, @config.Origin)? = None
          if !input.disabled() && tier.locations.get(0) is Some((path, false)) {
            let value = match context.tree.file(path) {
              Found(text) => @config.parse_file(context.formats, path.to_string(), text)
              Missing => raise @config.FileNotFound(path=path.to_string())
              Unknown => return Need([ReadFile(path)])
            }
            let kind = tier.sources[0].kind()
            controls = Some((value, { kind, source: conventions.display, priority: 300, location: Some(path.to_string()) }))
          }
          Some(@profiles.resolve_input(policy, input, controls?))
          }
        }
      }
      let profile_sources = match resolution {
        Some(resolution) => if conventions.layers is Some(_) { scan.ordered_profile_sources(tier, resolution) } else { conventions.profile_sources(tier.locations, resolution, extensions, tier.has_member) }
        None => []
      }
      if !scan.needs.is_empty() { return Need(scan.needs) }
      let ordered = [..sources]
      let mut inserted = false
      for source in tier.sources {
        if !inserted && source.kind() is File(LocalOverride | UserOverride) {
          ordered.append(profile_sources)
          inserted = true
        }
        ordered.push(source)
      }
      if !inserted { ordered.append(profile_sources) }
      Done(@config.Expansion::new(ordered, warnings=notes, profiles?=resolution))
    }
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
/// One discovery pass over the tree: the convention set, the load context,
/// the searched extensions, the requests for entries that the tree does not
/// hold yet, and the warnings.
priv struct Scan {
  conventions : Conventions
  context : @config.LoadContext
  extensions : Array[String]
  start : @config.FileTreePath?
  needs : Array[@config.FileRequest]
  notes : Array[@config.ConfigWarning]
  parsed : Map[@config.FileTreePath, @config.ConfigValue]
  documents : Map[@config.FileTreePath, Array[PrimaryDocument]]
}

///|
fn Scan::new(conventions : Conventions, context : @config.LoadContext, extensions : Array[String], notes : Array[@config.ConfigWarning]) -> Scan raise @config.ConfigError {
  let start = context.working_dir.filter(dir => dir.is_absolute()).map(normalize)
  { conventions, context, extensions, start, needs: [], notes, parsed: Map([]), documents: Map([]) }
}

///|
/// What a directory holds for the primary layouts and the legacy file.
priv enum DirConfig {
  /// The tree does not hold a listing yet.
  NotKnown
  /// No primary and no legacy file.
  NoFile
  /// One primary file.
  OneFile(@config.FileTreePath)
  /// No primary file, and the legacy file.
  LegacyAt(@config.FileTreePath)
  /// More than one primary file.
  Several
}

///|
/// How a project-tier primary was found.
priv enum FileKind {
  /// By walk-up, by the enclosing-workspace search, or as a member.
  Discovered
  /// From the `config` option.
  ExplicitFile
  /// The legacy fallback file.
  LegacyFile
}

///|
/// A project-tier primary: its path, the project root that it belongs to,
/// and how it was found.
priv struct ProjectFile {
  path : @config.FileTreePath
  root : @config.FileTreePath
  kind : FileKind
}

///|
/// The result of the walk-up.
priv enum Walk {
  /// The nearest directory with a primary or a legacy file.
  Root(ProjectFile)
  /// The nearest directory with a primary holds more than one.
  Crowded(@config.FileTreePath)
  /// No directory up to the boundary holds a primary.
  NoRoot
}

///|
/// A primary and the sources next to it: the environment file, the local
/// override and the user override, each when it applies.
priv struct Layer {
  primaries : Array[@config.ConfigSource]
  adjacent : Array[Array[@config.ConfigSource]]
  paths : Array[@config.FileTreePath]
  controls : Array[@profiles.ControlLayer]
}

///|
/// The project-tier sources in merge order, and whether a member is
/// selected.
priv struct Tier {
  sources : Array[@config.ConfigSource]
  has_member : Bool
  locations : Array[(@config.FileTreePath, Bool)]
  controls : Array[@profiles.ControlLayer]
}

///|
/// The project tier: the project or workspace primary, the selected member
/// primary, then their environment files, local overrides and user
/// overrides, workspace first.
///
/// `Explicit(path)` gives the primary with no walk-up, and `Skip` skips it.
/// Otherwise walk up from the working directory to the boundary, or to the
/// file-system root, and stop at the first directory that holds a primary
/// candidate or the legacy file. With no root, the candidate list at the
/// start directory reports `NotFound`. With the workspace part, the
/// enclosing-workspace search and member selection follow.
fn Conventions::project_sources(
  self : Conventions,
  project : ProjectInputs,
  scan : Scan,
  machine : Array[MachineSource],
) -> @config.LoadStep[Tier] raise @config.ConfigError {
  if self.root_policy is WorkspaceFirst(_) && project.options.config is Discover {
    return self.workspace_first_sources(project, scan, machine)
  }
  let context = scan.context
  let extensions = project.extensions
  let start = scan.start
  let stop = match self.boundary {
    Some(text) => {
      let dir = input_path(text, context.platform)
      match (dir.is_absolute(), start) {
        (true, _) => Some(normalize(dir))
        (false, Some(start)) => Some(normalize(start.resolve(dir)))
        (false, None) => None
      }
    }
    None => None
  }
  let alone = (sources : Array[@config.ConfigSource]) => {
    @config.LoadStep::Done({ sources, has_member: false, locations: [], controls: [] })
  }
  let file = match project.options.config {
    Explicit(path) => self.explicit_file(path, context, extensions)
    Skip => return alone([self.skipped_project()])
    Discover => {
      guard context.working_dir is Some(working_dir) else {
        scan.notes.push(
          note(self, "discovery has no working directory to start from"),
        )
        return alone([self.skipped_project()])
      }
      // The core joins a relative candidate to the working directory again,
      // and a relative directory has no parents to walk to.
      guard start is Some(start) else {
        scan.notes.push(
          note(
            self,
            "discovery needs an absolute working directory, not \{working_dir}",
          ),
        )
        return alone([self.skipped_project()])
      }
      if stop is Some(stop) && !start.is_within(stop) {
        raise OutsideBoundary(start=start.to_string(), boundary=stop.to_string())
      }
      match scan.walk_up(start, stop) {
        None => return Need(scan.needs)
        Some(Root(file)) => file
        // The core load checks the candidates and raises `Ambiguous`.
        Some(Crowded(dir)) =>
          return alone([self.primary(self.candidates(dir, extensions))])
        Some(NoRoot) => {
          if project.options.project is Some(selector) &&
            self.workspace is Some(_) {
            raise UnknownProject(selector~, workspace=start.to_string())
          }
          if self.layers is Some(_) {
            guard scan.ordered_layer(start, project, as_member=false) is Some(layer) else { return Need(scan.needs) }
            return Done(self.tier(layer, None))
          }
          return alone([self.primary(self.candidates(start, extensions))])
        }
      }
    }
  }
  guard self.workspace is Some(_) else {
    guard self.layer(file, project, scan, as_member=false) is Some(layer) else {
      return Need(scan.needs)
    }
    return Done(self.tier(layer, None))
  }
  guard scan.enclosing(file.root, stop) is Some(enclosing) else {
    return Need(scan.needs)
  }
  let (workspace, value) = match enclosing {
    Some(found) => (found.file, found.value)
    None =>
      match scan.value_of(file) {
        Found(value) => (file, value)
        Missing => raise FileNotFound(path=file.path.to_string())
        Unknown => return Need(scan.needs)
      }
  }
  let selected = if self.member_loading is ExplicitOnly && project.options.project is None { Some(None) } else { match (project.options.project, enclosing) {
    // The project file is a member of the enclosing workspace.
    (None, Some(_)) => Some(Some(file.root))
    (selector, _) => {
      guard scan.root_value(machine, value) is Some(root_value) else {
        return Need(scan.needs)
      }
      let declaration = self.declaration(root_value)
      match (selector, declaration) {
        (Some(selector), _) =>
          scan.selected_project(
            workspace.root,
            declaration,
            root_value,
            selector,
          )
        (None, Some(declaration)) =>
          scan.automatic_member(workspace.root, declaration, start)
        (None, None) => Some(None)
      }
    }
  } }
  guard selected is Some(member_dir) else { return Need(scan.needs) }
  guard self.layer(workspace, project, scan, as_member=false) is Some(base) else {
    return Need(scan.needs)
  }
  let chosen = match member_dir {
    None => None
    Some(dir) => {
      let layer = if enclosing is Some(_) && dir == file.root {
        self.layer(file, project, scan, as_member=true)
      } else {
        self.member_layer(dir, project, scan)
      }
      guard layer is Some(_) else { return Need(scan.needs) }
      layer
    }
  }
  Done(self.tier(base, chosen))
}

///|
/// The nearest directory from `start` up to the boundary `stop`, or to the
/// file-system root, that holds a primary or the legacy file. A legacy file
/// counts only when no primary exists there. `None` when the tree does not
/// hold a listing yet; the walk asks for the listings of one directory per
/// round, nearest first.
fn Scan::walk_up(
  self : Scan,
  start : @config.FileTreePath,
  stop : @config.FileTreePath?,
) -> Walk? raise @config.ConfigError {
  let mut dir = start
  while true {
    match self.config_at(dir) {
      NotKnown => return None
      Several => return Some(Crowded(dir))
      OneFile(path) => return Some(Root({ path, root: dir, kind: Discovered }))
      LegacyAt(path) => return Some(Root({ path, root: dir, kind: LegacyFile }))
      NoFile => ()
    }
    guard self.conventions.walk_up &&
      stop != Some(dir) &&
      dir.parent() is Some(parent) else {
      break
    }
    dir = parent
  }
  Some(NoRoot)
}

///|
/// What `dir` holds: the primary candidates of the three layouts, else the
/// legacy file. Asks for each listing that the tree does not hold, and for
/// each candidate that the listing holds as `Inaccessible`.
fn Scan::config_at(
  self : Scan,
  dir : @config.FileTreePath,
) -> DirConfig raise @config.ConfigError {
  if self.conventions.layers is Some(_) {
    match self.primary_paths(dir) {
      None => return NotKnown
      Some(paths) if paths.last() is Some(last) => return OneFile(last.path)
      Some(_) => ()
    }
    // With no ordered primary, retain the existing legacy fallback below.
    guard self.conventions.legacy is Some(legacy) else { return NoFile }
    let path = dir.join(legacy.name)
    return match self.context.tree.is_file(path) {
      Found(true) => LegacyAt(path)
      Found(false) | Missing => NoFile
      Unknown => { add_need(self.needs, self.context.tree.file_request(path)); NotKnown }
    }
  }
  let tree = self.context.tree
  let existing = []
  let mut known = true
  for candidate in self.conventions.candidates(dir, self.extensions) {
    match tree.is_file(candidate) {
      Found(true) => existing.push(candidate)
      Found(false) | Missing => ()
      Unknown => {
        add_need(self.needs, tree.file_request(candidate))
        known = false
      }
    }
  }
  // The host answers for each candidate first, so the error of an
  // inaccessible candidate passes out even when two others exist.
  guard known else { return NotKnown }
  if existing.length() > 1 {
    return Several
  }
  if existing is [path] {
    return OneFile(path)
  }
  guard self.conventions.legacy is Some(legacy) else { return NoFile }
  let path = dir.join(legacy.name)
  match tree.is_file(path) {
    Found(true) => LegacyAt(path)
    Found(false) | Missing => NoFile
    Unknown => {
      add_need(self.needs, tree.file_request(path))
      NotKnown
    }
  }
}

///|
/// The parsed value of `file`, with the legacy format and decoder for a
/// legacy file and the registered formats for another file. Asks for the
/// file when the tree does not hold its text.
fn Scan::value_of(
  self : Scan,
  file : ProjectFile,
) -> @config.Lookup[@config.ConfigValue] raise @config.ConfigError {
  if self.conventions.layers is Some(_) && file.kind is Discovered {
    return match self.primary_documents(file.root) {
      None => Unknown
      Some(documents) => Found(@config.build(documents.map(document => self.document_source(document, Workspace))).value())
    }
  }
  if self.conventions.layers is Some(_) && file.kind is ExplicitFile {
    return self.read_document(file.path)
  }
  match self.context.tree.file(file.path) {
    Found(text) =>
      Found(
        match (file.kind, self.conventions.legacy) {
          (LegacyFile, Some(legacy)) =>
            (legacy.decode)((legacy.format.parse)(text, file.path.to_string()))
          _ =>
            @config.parse_file(self.context.formats, file.path.to_string(), text)
        },
      )
    Missing => Missing
    Unknown => {
      add_need(self.needs, ReadFile(file.path))
      Unknown
    }
  }
}

///|
/// Add a `Note` warning one time.
fn Scan::warn(self : Scan, message : String) -> Unit {
  let warning = note(self.conventions, message)
  if !self.notes.contains(warning) {
    self.notes.push(warning)
  }
}

///|
/// The primary source of `file` and the sources next to it. A member
/// primary has the role `Member`. Another primary has the role `Workspace`,
/// `Explicit` or `Legacy`. A legacy file has no adjacent source. `None` when
/// the tree does not hold the text of a legacy file yet.
fn Conventions::layer(
  self : Conventions,
  file : ProjectFile,
  project : ProjectInputs,
  scan : Scan,
  as_member~ : Bool,
  parsed? : @config.ConfigValue,
) -> Layer? raise @config.ConfigError {
  if self.layers is Some(_) && file.kind is Discovered {
    return scan.ordered_layer(file.root, project, as_member~)
  }
  let primary = match file.kind {
    Discovered if parsed is Some(value) =>
      @config.ConfigSource::parsed_file(file.path.to_string(), value,
        role=if as_member { Member } else { Workspace }, name=self.display)
    Discovered =>
      @config.ConfigSource::candidates(
        texts(self.candidates(file.root, project.extensions)),
        display=self.display,
        role=if as_member { Member } else { Workspace },
      )
    ExplicitFile if self.layers is Some(_) => match scan.read_document(file.path) {
      Found(value) => @config.ConfigSource::parsed_file(file.path.to_string(), value, role=if as_member { Member } else { Explicit }, name=self.display)
      Missing => raise @config.FileNotFound(path=file.path.to_string())
      Unknown => return None
    }
    ExplicitFile =>
      @config.ConfigSource::file(
        file.path.to_string(),
        role=if as_member { Member } else { Explicit },
        name=self.display,
      )
    LegacyFile =>
      match scan.value_of(file) {
        Found(value) =>
          return Some({
            primaries: [@config.ConfigSource::parsed_file(
              file.path.to_string(),
              value,
              role=if as_member { Member } else { Legacy },
              name=self.display,
            )],
            adjacent: [],
            paths: [],
            controls: [],
          })
        Missing => raise FileNotFound(path=file.path.to_string())
        Unknown => return None
      }
  }
  if self.layers is Some(_) {
    let paths = if self.adjacent(file.path, project.extensions) is Some(_) { [file.path] } else { [] }
    let adjacent = if paths.is_empty() { [] } else {
      guard scan.ordered_overrides(self.anchors(paths, project.extensions), project) is Some(stages) else { return None }
      stages
    }
    let controls = if as_member || paths.is_empty() { [] } else {
      match scan.read_document(file.path) {
        Found(value) => [scan.control_layer(file.path, value, Explicit)]
        Missing => raise @config.FileNotFound(path=file.path.to_string())
        Unknown => return None
      }
    }
    return Some({ primaries: [primary], adjacent, paths, controls })
  }
  Some({ primaries: [primary], adjacent: self.overrides(file.path, project).map(source => source.map(value => [value]).unwrap_or([])), paths: if self.adjacent(file.path, project.extensions) is Some(_) { [file.path] } else { [] }, controls: [] })
}

///|
/// The layer of the selected member in `dir`. With no primary there, or more
/// than one, the member source is the candidate list, so the report shows
/// `NotFound` with every candidate, or the core load raises `Ambiguous`.
fn Conventions::member_layer(
  self : Conventions,
  dir : @config.FileTreePath,
  project : ProjectInputs,
  scan : Scan,
) -> Layer? raise @config.ConfigError {
  match scan.config_at(dir) {
    NotKnown => None
    OneFile(path) =>
      self.layer({ path, root: dir, kind: Discovered }, project, scan, as_member=true)
    LegacyAt(path) =>
      self.layer({ path, root: dir, kind: LegacyFile }, project, scan, as_member=true)
    NoFile | Several => if self.layers is Some(_) {
      scan.ordered_layer(dir, project, as_member=true)
    } else {
      Some({
        primaries: [@config.ConfigSource::candidates(
          texts(self.candidates(dir, project.extensions)),
          display=self.display,
          role=Member,
        )],
        adjacent: [],
        paths: [],
        controls: [],
      })
    }
  }
}

///|
/// The explicit primary at `given`. The text is in the native form of the
/// platform, so on Windows `\` works. A relative path joins the working
/// directory. The project root is the directory of the file, or the directory
/// that holds `.<app>/` or `.config/<app>/` for those layouts.
fn Conventions::explicit_file(
  self : Conventions,
  given : String,
  context : @config.LoadContext,
  extensions : Array[String],
) -> ProjectFile raise @config.ConfigError {
  let path = input_path(given, context.platform)
  let resolved = if path.is_absolute() {
    normalize(path)
  } else {
    match context.working_dir {
      Some(dir) if dir.is_absolute() => normalize(dir.resolve(path))
      _ => path
    }
  }
  let root = match self.adjacent(resolved, extensions) {
    Some((dir, "config")) if parent_of(dir).name() == Some(".config") =>
      parent_of(parent_of(dir))
    Some((dir, _)) if dir.name() == Some(".\{self.name}") => parent_of(dir)
    _ => parent_of(resolved)
  }
  { path: resolved, root, kind: ExplicitFile }
}

///|
/// The environment file, local override and user override sources next to
/// the primary at `path`, each when it applies, or none when the path has no
/// standard layout. In isolated mode the overrides report `Skipped`; the
/// environment file stays.
fn Conventions::overrides(
  self : Conventions,
  path : @config.FileTreePath,
  project : ProjectInputs,
) -> Array[@config.ConfigSource?] raise @config.ConfigError {
  let { options, environment, extensions } = project
  guard self.adjacent(path, extensions) is Some((dir, stem)) else { return [] }
  let sources = [
    environment.map(name => self.environment_file(dir, stem, name, extensions)),
  ]
  let kinds : Array[(Part, @config.FileRole, String)] = [
    (LocalOverrides, LocalOverride, "local"),
    (UserOverrides, UserOverride, "user"),
  ]
  for kind in kinds {
    let (part, role, word) = kind
    guard self.has(part) else {
      sources.push(None)
      continue
    }
    sources.push(
      Some(
        if options.isolated {
          @config.ConfigSource::skipped(File(role), name=self.display)
        } else {
          @config.ConfigSource::candidates(
            texts(
              extensions.map(extension => {
                dir.child("\{stem}.\{word}.\{extension}")
              }),
            ),
            display=self.display,
            role~,
            name=self.display,
          )
        },
      ),
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
  path : @config.FileTreePath,
  extensions : Array[String],
) -> (@config.FileTreePath, String)? {
  guard path.parent() is Some(dir) && path.name() is Some(file) else {
    return None
  }
  for extension in extensions {
    if file == "\{self.name}.\{extension}" {
      return Some((dir, self.name))
    }
    if file == "config.\{extension}" &&
      dir.name() == Some(self.name) &&
      parent_of(dir).name() == Some(".config") {
      return Some((dir, "config"))
    }
  }
  None
}

///|
/// `source` without the key paths `paths`, through the core `exclude`.
fn filtered(
  source : @config.ConfigSource,
  paths : Array[@config.KeyPath],
  warn~ : Bool,
) -> @config.ConfigSource {
  if paths.is_empty() {
    source
  } else {
    source.exclude(paths, warn~)
  }
}

///|
/// The key paths of the text forms `texts`.
fn key_paths(
  texts : Array[String],
) -> Array[@config.KeyPath] raise @config.ConfigError {
  texts.map(text => @config.KeyPath::parse(text))
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
/// with environments off, and the project with no workspace part.
fn unread_options(
  conventions : Conventions,
  options : DiscoveryOptions,
) -> Array[@config.ConfigWarning] {
  let notes = []
  if options.profiles != Unspecified && conventions.profiles is None {
    notes.push(note(conventions, "profiles are off, so discovery ignores the profiles option"))
  }
  if options.environment is Some(_) && conventions.environments is None {
    notes.push(
      note(
        conventions, "environments are off, so discovery ignores the environment option",
      ),
    )
  }
  if options.project is Some(_) && conventions.workspace is None {
    notes.push(
      note(
        conventions, "the convention set has no workspace part, so discovery ignores the project option",
      ),
    )
  }
  notes
}

///|
/// The primary candidates in `dir`, layout by layout, in extension order.
fn Conventions::candidates(
  self : Conventions,
  dir : @config.FileTreePath,
  extensions : Array[String],
) -> Array[@config.FileTreePath] raise @config.ConfigError {
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
      paths.push(dir.join(relative))
    }
  }
  paths
}

///|
fn Conventions::primary(
  self : Conventions,
  candidates : Array[@config.FileTreePath],
) -> @config.ConfigSource {
  @config.ConfigSource::candidates(
    texts(candidates),
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
/// The parsed path of the input text `text`. With a platform, the text is in
/// the native form of that platform, so `\` separators work on Windows.
fn input_path(
  text : String,
  platform : @config.Platform?,
) -> @config.FileTreePath raise @config.ConfigError {
  match platform {
    Some(platform) => @config.FileTreePath::from_native(text, platform)
    None => @config.FileTreePath::parse(text)
  }
}

///|
/// `path` with each `..` name applied to the name before it. `..` never goes
/// above the root. Discovery applies this rule to the paths that a run gives,
/// such as the explicit file `../configs/acme.toml` or a relative variable,
/// before it uses them. The file-tree path itself never applies `..`.
fn normalize(
  path : @config.FileTreePath,
) -> @config.FileTreePath raise @config.ConfigError {
  let mut result = path.root()
  for name in path.names() {
    result = if name == ".." {
      result.parent().unwrap_or(result)
    } else {
      result.child(name)
    }
  }
  result
}

///|
/// The directory of `path`, or `path` itself at a root.
fn parent_of(path : @config.FileTreePath) -> @config.FileTreePath {
  path.parent().unwrap_or(path)
}

///|
/// The text form of each path, for a source or a report.
fn texts(paths : Array[@config.FileTreePath]) -> Array[String] {
  paths.map(path => path.to_string())
}

///|
fn Conventions::profile_sources(
  self : Conventions,
  locations : Array[(@config.FileTreePath, Bool)],
  resolution : @config.ProfileResolution,
  extensions : Array[String],
  has_member : Bool,
) -> Array[@config.ConfigSource] raise @config.ConfigError {
  let sources = []
  for name in resolution.active().names() {
    for location in locations {
      let (path, is_member) = location
      guard self.adjacent(path, extensions) is Some((dir, stem)) else { continue }
      let source = @config.ConfigSource::candidates(
        texts(extensions.map(extension => dir.child("\{stem}.profile.\{name}.\{extension}"))),
        display=self.display, role=ProfileFile(name), name=self.display,
      )
      let filters = if is_member { key_paths(self.member_scope) } else if has_member { key_paths(self.inherited) } else { [] }
      sources.push(filtered(source, filters, warn=is_member))
    }
  }
  sources
}
