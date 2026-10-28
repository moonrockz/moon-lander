///|
/// The root selection rule. The section path is parsed once at the boundary.
pub(all) enum RootPolicy {
  /// Retain nearest-file discovery and legacy enclosing-member selection.
  NearestFile
  /// Stop at the nearest document that contains this workspace section.
  WorkspaceFirst(@config.KeyPath)
}

///|
/// Whether discovery selects and loads one workspace member.
pub(all) enum MemberLoading {
  /// Select a member from the working directory, default or sole member.
  Automatic
  /// Load a member only when DiscoveryOptions.project explicitly selects it.
  ExplicitOnly
}

///|
/// Root evidence from a pure discovery pass. A nearest project is the first
/// primary encountered, including a primary that also declares a workspace.
pub struct RootEvidence {
  priv project : Enclosing?
  priv workspace : Enclosing?
  priv sources : Array[@config.ConfigSource]
}

///|
/// The nearest primary's project directory, when one exists.
pub fn RootEvidence::nearest_project(self : RootEvidence) -> @config.FileTreePath? {
  self.project.map(found => found.file.root)
}

///|
/// The selected declared workspace directory, when one exists.
pub fn RootEvidence::workspace(self : RootEvidence) -> @config.FileTreePath? {
  self.workspace.map(found => found.file.root)
}

///|
/// The selected root's primary sources, already parsed, in merge order. This
/// does not choose a member or read any member's contents.
pub fn RootEvidence::sources(self : RootEvidence) -> Array[@config.ConfigSource] {
  self.sources.copy()
}

///|
fn root_evidence(
  conventions : Conventions,
  project : Enclosing?,
  workspace : Enclosing?,
) -> RootEvidence raise @config.ConfigError {
  let selected = if workspace is Some(_) { workspace } else { project }
  let sources = match selected {
    None => []
    Some(found) => [@config.ConfigSource::parsed_file(
      found.file.path.to_string(), found.value,
      name=conventions.display,
      role=match found.file.kind {
        LegacyFile => Legacy
        ExplicitFile => Explicit
        Discovered => Workspace
      },
    )]
  }
  { project, workspace, sources }
}

///|
/// Resolve the explicit boundary once against the normalized working directory.
fn Conventions::root_bounds(
  self : Conventions,
  context : @config.LoadContext,
) -> (@config.FileTreePath?, @config.FileTreePath?) raise @config.ConfigError {
  let start = context.working_dir.filter(dir => dir.is_absolute()).map(normalize)
  let stop = match self.boundary {
    None => None
    Some(text) => {
      let dir = input_path(text, context.platform)
      if dir.is_absolute() {
        Some(normalize(dir))
      } else {
        start.map(start => normalize(start.resolve(dir)))
      }
    }
  }
  (start, stop)
}

///|
/// Inspect roots through the same partial-tree protocol as configuration load.
/// No member is selected. Pass the returned primary sources to public merge
/// APIs and retain an application-owned all-member walk when needed.
pub fn Conventions::roots(
  self : Conventions,
  context : @config.LoadContext,
  options? : DiscoveryOptions = DiscoveryOptions::new(),
) -> @config.LoadStep[RootEvidence] raise @config.ConfigError {
  if options.config is Skip { return Done(root_evidence(self, None, None)) }
  let (start, stop) = self.root_bounds(context)
  let scan : Scan = { conventions: self, context, extensions: searched_extensions(context.formats), needs: [], notes: [] }
  if options.config is Explicit(path) {
    let file = self.explicit_file(path, context, scan.extensions)
    return scan.nearest_roots(file, stop)
  }
  guard start is Some(start) else { return Done(root_evidence(self, None, None)) }
  if stop is Some(stop) && !start.is_within(stop) {
    raise OutsideBoundary(start=start.to_string(), boundary=stop.to_string())
  }
  match self.root_policy {
    WorkspaceFirst(section) => scan.workspace_roots(start, stop, section)
    NearestFile => match scan.walk_up(start, stop) {
      None => Need(scan.needs)
      Some(NoRoot) => Done(root_evidence(self, None, None))
      Some(Crowded(dir)) => scan.ambiguous_root(dir)
      Some(Root(file)) => scan.nearest_roots(file, stop)
    }
  }
}

///|
fn[T] Scan::ambiguous_root(self : Scan, dir : @config.FileTreePath) -> T raise @config.ConfigError {
  let candidates = self.conventions.candidates(dir, self.extensions).filter(path => self.context.tree.is_file(path) is Found(true))
  raise @config.Ambiguous(display=self.conventions.display, location=dir.to_string(), candidates=candidates.map(path => path.to_string()))
}

///|
fn Scan::nearest_roots(
  self : Scan,
  file : ProjectFile,
  stop : @config.FileTreePath?,
) -> @config.LoadStep[RootEvidence] raise @config.ConfigError {
  let project = match self.value_of(file) {
    Found(value) => { file, value }
    Missing => raise @config.FileNotFound(path=file.path.to_string())
    Unknown => return Need(self.needs)
  }
  let workspace = if self.conventions.workspace is Some(_) {
    match self.enclosing(file.root, stop) {
      None => return Need(self.needs)
      Some(Some(found)) => Some(found)
      Some(None) => if self.conventions.declaration(project.value) is Some(_) { Some(project) } else { None }
    }
  } else { None }
  Done(root_evidence(self.conventions, Some(project), workspace))
}

///|
fn Scan::workspace_roots(
  self : Scan,
  start : @config.FileTreePath,
  stop : @config.FileTreePath?,
  section : @config.KeyPath,
) -> @config.LoadStep[RootEvidence] raise @config.ConfigError {
  let mut nearest : Enclosing? = None
  let mut dir = start
  while true {
    let file = match self.config_at(dir) {
      NotKnown => return Need(self.needs)
      Several => self.ambiguous_root(dir)
      NoFile => None
      OneFile(path) => Some(ProjectFile::{ path, root: dir, kind: Discovered })
      LegacyAt(path) => Some(ProjectFile::{ path, root: dir, kind: LegacyFile })
    }
    if file is Some(file) {
      let value = match self.value_of(file) {
        Found(value) => value
        Missing => raise @config.FileNotFound(path=file.path.to_string())
        Unknown => return Need(self.needs)
      }
      let found : Enclosing = { file, value }
      if nearest is None { nearest = Some(found) }
      let document = self.conventions.discovery_value(value)
      if document.get(section) is Some(_) {
        // A section must be an object, including an empty one. Bind at this
        // document boundary so a scalar gives the ordinary typed Decode error.
        let _ : Map[String, Json] = @config.bind(document, section.to_string())
        return Done(root_evidence(self.conventions, nearest, Some(found)))
      }
    }
    guard self.conventions.walk_up && stop != Some(dir) && dir.parent() is Some(parent) else { break }
    dir = parent
  }
  Done(root_evidence(self.conventions, nearest, None))
}

///|
fn Conventions::workspace_first_sources(
  self : Conventions,
  project : ProjectInputs,
  scan : Scan,
  machine : Array[MachineSource],
) -> @config.LoadStep[Tier] raise @config.ConfigError {
  let evidence = match self.roots(scan.context, options=project.options) {
    Need(requests) => return Need(requests)
    Done(evidence) => evidence
  }
  let selected = if evidence.workspace is Some(_) { evidence.workspace } else { evidence.project }
  guard selected is Some(base) else {
    if project.options.project is Some(selector) && self.workspace is Some(_) && scan.context.working_dir is Some(start) {
      raise @config.UnknownProject(selector~, workspace=start.to_string())
    }
    let sources = match scan.context.working_dir {
      Some(start) if start.is_absolute() => [self.primary(self.candidates(normalize(start), project.extensions))]
      _ => [self.skipped_project()]
    }
    return Done({ sources, has_member: false, locations: [] })
  }
  let layer = self.layer(base.file, project, scan, as_member=false, parsed=base.value)
  guard layer is Some(layer) else { return Need(scan.needs) }
  let selection = if (self.member_loading is ExplicitOnly && project.options.project is None) || self.workspace is None {
    Some(None)
  } else {
    guard scan.root_value(machine, base.value) is Some(value) else { return Need(scan.needs) }
    let declaration = self.declaration(value)
    match project.options.project {
      Some(selector) => scan.selected_project(base.file.root, declaration, value, selector)
      None => match declaration {
        Some(declaration) if evidence.workspace is Some(_) => scan.automatic_member(base.file.root, declaration, scan.context.working_dir)
        _ => Some(None)
      }
    }
  }
  guard selection is Some(member_dir) else { return Need(scan.needs) }
  guard member_dir is Some(dir) else {
    return Done({ sources: [layer.primary, ..layer.adjacent.filter_map(source => source)], has_member: false, locations: layer.path.map(path => [(path, false)]).unwrap_or([]) })
  }
  let chosen = match evidence.project {
    Some(found) if found.file.root == dir => self.layer(found.file, project, scan, as_member=true, parsed=found.value)
    _ => self.member_layer(dir, project, scan)
  }
  guard chosen is Some(chosen) else { return Need(scan.needs) }
  let inherited = key_paths(self.inherited)
  let scoped = key_paths(self.member_scope)
  let sources = [filtered(layer.primary, inherited, warn=false), filtered(chosen.primary, scoped, warn=true)]
  for index in 0..<layer.adjacent.length().max(chosen.adjacent.length()) {
    if layer.adjacent.get(index) is Some(Some(source)) { sources.push(filtered(source, inherited, warn=false)) }
    if chosen.adjacent.get(index) is Some(Some(source)) { sources.push(filtered(source, scoped, warn=true)) }
  }
  Done({ sources, has_member: true, locations: [..layer.path.map(path => [(path, false)]).unwrap_or([]), ..chosen.path.map(path => [(path, true)]).unwrap_or([])] })
}
