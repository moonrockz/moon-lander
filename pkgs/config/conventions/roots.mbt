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
  project : Enclosing?,
  workspace : Enclosing?,
) -> RootEvidence {
  let selected = if workspace is Some(_) { workspace } else { project }
  let sources = selected.map(found => found.primaries.copy()).unwrap_or([])
  { project, workspace, sources }
}

///|
/// Resolve the explicit boundary once against the normalized working directory.
fn Conventions::root_bounds(
  self : Conventions,
  context : @config.LoadContext,
  start : @config.FileTreePath?,
) -> (@config.FileTreePath?, @config.FileTreePath?) raise @config.ConfigError {
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
  self.check_formats(context.formats)
  let scan = Scan::new(self, context, searched_extensions(context.formats), [], options~)
  scan.roots(options)
}

///|
/// Internal discovery already checked the final policy. Share its scan and
/// canonical start rather than re-entering a public boundary and reparsing.
fn Scan::roots(self : Scan, options : DiscoveryOptions) -> @config.LoadStep[RootEvidence] raise @config.ConfigError {
  let options = self.conventions.primary_options(options)
  if options.config is Skip { return Done(root_evidence(None, None)) }
  let (start, stop) = self.conventions.root_bounds(self.context, self.start)
  if options.config is Explicit(path) {
    let file = self.conventions.explicit_file(path, self.context, self.extensions)
    return self.nearest_roots(file, stop)
  }
  guard start is Some(start) else { return Done(root_evidence(None, None)) }
  if stop is Some(stop) && !start.is_within(stop) {
    raise OutsideBoundary(start=start.to_string(), boundary=stop.to_string())
  }
  match self.conventions.root_policy {
    WorkspaceFirst(section) => self.workspace_roots(start, stop, section)
    NearestFile => match self.walk_up(start, stop) {
      None => Need(self.needs)
      Some(NoRoot) => Done(root_evidence(None, None))
      Some(Crowded(dir)) => self.ambiguous_root(dir)
      Some(Root(file)) => self.nearest_roots(file, stop)
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
    Found(value) => self.found(file, value)
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
  Done(root_evidence(Some(project), workspace))
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
      let found = self.found(file, value)
      if nearest is None { nearest = Some(found) }
      let document = self.conventions.discovery_value(value)
      if document.get(section) is Some(_) {
        // A section must be an object, including an empty one. Bind at this
        // document boundary so a scalar gives the ordinary typed Decode error.
        let _ : Map[String, Json] = @config.bind(document, section.to_string())
        return Done(root_evidence(nearest, Some(found)))
      }
    }
    guard self.conventions.walk_up && stop != Some(dir) && dir.parent() is Some(parent) else { break }
    dir = parent
  }
  Done(root_evidence(nearest, None))
}

///|
fn Conventions::workspace_first_sources(
  self : Conventions,
  project : ProjectInputs,
  scan : Scan,
  machine : Array[MachineSource],
) -> @config.LoadStep[Tier] raise @config.ConfigError {
  let evidence = match scan.roots(project.options) {
    Need(requests) => return Need(requests)
    Done(evidence) => evidence
  }
  let selected = if evidence.workspace is Some(_) { evidence.workspace } else { evidence.project }
  guard selected is Some(base) else {
    if project.options.project is Some(selector) && self.workspace is Some(_) && scan.start is Some(start) {
      raise @config.UnknownProject(selector~, workspace=start.to_string())
    }
    if self.layers is Some(_) && scan.start is Some(start) {
      guard scan.ordered_layer(start, project, as_member=false) is Some(layer) else { return Need(scan.needs) }
      return Done(self.tier(layer, None))
    }
    let sources = match scan.start {
      Some(start) => [self.primary(self.candidates(start, project.extensions))]
      _ => [self.skipped_project()]
    }
    return Done({ sources, has_member: false, locations: [], controls: [] })
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
        Some(declaration) if evidence.workspace is Some(_) => scan.automatic_member(base.file.root, declaration, scan.start)
        _ => Some(None)
      }
    }
  }
  guard selection is Some(member_dir) else { return Need(scan.needs) }
  guard member_dir is Some(dir) else {
    return Done(self.tier(layer, None))
  }
  let chosen = match evidence.project {
    Some(found) if found.file.root == dir => self.layer(found.file, project, scan, as_member=true, parsed=found.value)
    _ => self.member_layer(dir, project, scan)
  }
  guard chosen is Some(chosen) else { return Need(scan.needs) }
  Done(self.tier(layer, Some(chosen)))
}
