///|
priv struct SelectedPrimary {
  path : @config.FileTreePath
  supplemental : SupplementalFile?
}

///|
priv struct PrimaryDocument {
  selected : SelectedPrimary
  value : @config.ConfigValue
}

///|
/// Establish presence and ambiguity before requesting any file contents.
fn Scan::existing(self : Scan, paths : Array[@config.FileTreePath]) -> Array[@config.FileTreePath]? raise @config.ConfigError {
  let existing = []
  let mut known = true
  for path in paths {
    match self.context.tree.is_file(path) {
      Found(true) => if !existing.contains(path) { existing.push(path) }
      Found(false) | Missing => ()
      Unknown => { add_need(self.needs, self.context.tree.file_request(path)); known = false }
    }
  }
  guard known else { return None }
  if existing.length() > 1 {
    raise @config.Ambiguous(display=self.conventions.display,
      location=@config.FileTreePath::common_dir(paths).map(path => path.to_string()).unwrap_or("."),
      candidates=texts(existing))
  }
  Some(existing)
}

///|
/// Only selected physical identities enter this cache. A supplemental transform
/// runs with its parser once in a pass and is reused by classification and load.
fn Scan::read_document(
  self : Scan,
  path : @config.FileTreePath,
  supplemental? : SupplementalFile,
) -> @config.Lookup[@config.ConfigValue] raise @config.ConfigError {
  let path = normalize(path)
  if self.parsed.get(path) is Some(value) { return Found(value) }
  match self.context.tree.file(path) {
    Found(text) => {
      let value = @config.parse_file(self.context.formats, path.to_string(), text)
      let value = match supplemental { Some(file) => (file.transform)(value); None => value }
      self.parsed[path] = value
      Found(value)
    }
    Missing => Missing
    Unknown => { add_need(self.needs, ReadFile(path)); Unknown }
  }
}

///|
fn Scan::primary_paths(self : Scan, dir : @config.FileTreePath) -> Array[SelectedPrimary]? raise @config.ConfigError {
  guard self.conventions.layers is Some(layers) else { return Some([]) }
  let selected = []
  let mut known = true
  for group in layers.groups {
    if group.supplemental is Some(file) {
      let path = dir.child(file.name)
      match self.existing([path]) {
        Some([path]) => selected.push({ path, supplemental: Some(file) })
        Some(_) => ()
        None => known = false
      }
    }
    let paths = self.conventions.candidates(dir, group.extensions.map(extension => extension.text))
    match self.existing(paths) {
      Some([path]) => selected.push({ path, supplemental: None })
      Some(_) => ()
      None => known = false
    }
  }
  if known { Some(selected) } else { None }
}

///|
fn Scan::primary_documents(self : Scan, dir : @config.FileTreePath) -> Array[PrimaryDocument]? raise @config.ConfigError {
  let dir = normalize(dir)
  if self.documents.get(dir) is Some(documents) { return Some(documents) }
  guard self.primary_paths(dir) is Some(paths) else { return None }
  let documents = []
  let mut known = true
  for selected in paths {
    match self.read_document(selected.path, supplemental?=selected.supplemental) {
      Found(value) => documents.push({ selected, value })
      Missing => raise @config.FileNotFound(path=selected.path.to_string())
      Unknown => known = false
    }
  }
  guard known else { return None }
  self.documents[dir] = documents
  Some(documents)
}

///|
fn Scan::document_source(self : Scan, document : PrimaryDocument, role : @config.FileRole) -> @config.ConfigSource raise @config.ConfigError {
  @config.ConfigSource::parsed_file(document.selected.path.to_string(), document.value, role~, name=self.conventions.display)
}

///|
fn Scan::found(self : Scan, file : ProjectFile, value : @config.ConfigValue) -> Enclosing raise @config.ConfigError {
  let primaries = if self.conventions.layers is Some(_) && file.kind is Discovered {
    self.documents.get(file.root).unwrap_or([]).map(document => self.document_source(document, Workspace))
  } else {
    [@config.ConfigSource::parsed_file(file.path.to_string(), value,
      name=self.conventions.display, role=match file.kind {
        LegacyFile => Legacy
        ExplicitFile => Explicit
        Discovered => Workspace
      })]
  }
  { file, value, primaries }
}

///|
fn Scan::source_for(
  self : Scan,
  paths : Array[@config.FileTreePath],
  role : @config.FileRole,
  supplemental? : SupplementalFile,
  omit_selected? : Bool = true,
) -> Array[@config.ConfigSource]? raise @config.ConfigError {
  guard self.existing(paths) is Some(existing) else { return None }
  guard existing is [path] else {
    return Some([@config.ConfigSource::candidates(texts(paths), display=self.conventions.display, role~, name=self.conventions.display)])
  }
  match self.read_document(path, supplemental?) {
    Found(value) => {
      let source = @config.ConfigSource::parsed_file(path.to_string(), value, role~, name=self.conventions.display)
      Some(if omit_selected { self.keep_source(path, source) } else { [source] })
    }
    Missing => raise @config.FileNotFound(path=path.to_string())
    Unknown => None
  }
}

///|
fn Scan::ordered_layer(
  self : Scan,
  root : @config.FileTreePath,
  project : ProjectInputs,
  as_member~ : Bool,
) -> Layer? raise @config.ConfigError {
  guard self.conventions.layers is Some(layers) else { return None }
  guard self.primary_documents(root) is Some(documents) else { return None }
  let role : @config.FileRole = if as_member { Member } else { Workspace }
  let primaries = []
  let mut known = true
  for group in layers.groups {
    if group.supplemental is Some(file) {
      match self.source_for([root.child(file.name)], role, supplemental=file) {
        Some(sources) => primaries.append(sources)
        None => known = false
      }
    }
    let paths = self.conventions.candidates(root, group.extensions.map(extension => extension.text))
    match self.source_for(paths, role) {
      Some(sources) => primaries.append(sources)
      None => known = false
    }
  }
  guard known else { return None }
  if documents.is_empty() { return Some({ primaries, adjacent: [], paths: [], controls: [] }) }
  // Only ordinary layouts supply adjacent stems. A supplemental-only root uses
  // the standard application layout rather than a supplemental-file stem.
  let paths = documents.filter_map(document => if document.selected.supplemental is None { Some(document.selected.path) } else { None })
  if paths.is_empty() {
    paths.push(root.child("\{self.conventions.name}.\{layers.groups[0].extensions[0].text}"))
  }
  let anchors = self.conventions.anchors(paths, project.extensions)
  let adjacent = self.ordered_overrides(anchors, project)
  guard known && adjacent is Some(adjacent) else { return None }
  let controls = if as_member || self.conventions.profiles is None { [] } else { documents.map(document => self.control_layer(document.selected.path, document.value, Workspace)) }
  Some({ primaries, adjacent, paths, controls })
}

///|
fn Scan::control_layer(self : Scan, path : @config.FileTreePath, value : @config.ConfigValue, role : @config.FileRole) -> @profiles.ControlLayer raise @config.ConfigError {
  @profiles.ControlLayer::new(value, { kind: File(role), source: self.conventions.display, priority: 300, location: Some(path.to_string()) })
}

///|
fn Scan::ordered_profile_sources(
  self : Scan,
  tier : Tier,
  resolution : @config.ProfileResolution,
) -> Array[@config.ConfigSource] raise @config.ConfigError {
  let sources = []
  for name in resolution.active().names() {
    for is_member in [false, true] {
      let paths = tier.locations.filter_map(location => if location.1 == is_member { Some(location.0) } else { None })
      let anchors = self.conventions.anchors(paths, self.extensions)
      if anchors.is_empty() { continue }
      guard self.adjacent_sources(anchors, "profile.\{name}", ProfileFile(name)) is Some(stage) else { continue }
      let filters = if is_member { key_paths(self.conventions.member_scope) } else if tier.has_member { key_paths(self.conventions.inherited) } else { [] }
      sources.append(stage.map(source => filtered(source, filters, warn=is_member)))
    }
  }
  sources
}

///|
fn Conventions::anchors(self : Conventions, paths : Array[@config.FileTreePath], extensions : Array[String]) -> Array[(@config.FileTreePath, String)] {
  let anchors = []
  for path in paths {
    if self.adjacent(path, extensions) is Some(anchor) && !anchors.contains(anchor) {
      anchors.push(anchor)
    }
  }
  anchors
}

///|
fn Scan::adjacent_sources(
  self : Scan,
  anchors : Array[(@config.FileTreePath, String)],
  suffix : String,
  role : @config.FileRole,
) -> Array[@config.ConfigSource]? raise @config.ConfigError {
  let groups = self.conventions.layers.map(layers => layers.groups.map(group => group.extensions.map(extension => extension.text))).unwrap_or([self.extensions])
  let sources = []
  let mut known = true
  for extensions in groups {
    let paths = []
    for (dir, stem) in anchors {
      for extension in extensions {
        let path = dir.child("\{stem}.\{suffix}.\{extension}")
        if !paths.contains(path) { paths.push(path) }
      }
    }
    match self.source_for(paths, role) {
      Some(stage) => sources.append(stage)
      None => known = false
    }
  }
  if known { Some(sources) } else { None }
}

///|
fn Scan::ordered_overrides(
  self : Scan,
  anchors : Array[(@config.FileTreePath, String)],
  project : ProjectInputs,
) -> Array[Array[@config.ConfigSource]]? raise @config.ConfigError {
  let stages = []
  let mut known = true
  match project.environment {
    None => stages.push([])
    Some(name) => match self.adjacent_sources(anchors, name, EnvironmentFile) {
      Some(sources) => stages.push(sources)
      None => { stages.push([]); known = false }
    }
  }
  for (part, role, suffix) in [(LocalOverrides, @config.FileRole::LocalOverride, "local"), (UserOverrides, UserOverride, "user")] {
    if !self.conventions.has(part) { stages.push([]); continue }
    if project.options.isolated {
      let count = self.conventions.layers.map(layers => layers.groups.length()).unwrap_or(1)
      let sources = Array::makei(count, _ => @config.ConfigSource::skipped(File(role), name=self.conventions.display))
      stages.push(sources)
      continue
    }
    match self.adjacent_sources(anchors, suffix, role) {
      Some(sources) => stages.push(sources)
      None => { stages.push([]); known = false }
    }
  }
  if known { Some(stages) } else { None }
}

///|
/// Reuse existing directory policy, then divide each enabled stage by the
/// explicit format order. Supplemental files remain below ordinary candidates.
fn Scan::machine_sources(self : Scan, options : DiscoveryOptions) -> Array[MachineSource] raise @config.ConfigError {
  let ordinary = self.conventions.machine_sources(options, self.context, self.extensions, self.notes)
  guard self.conventions.layers is Some(layers) else {
    if self.conventions.selected_file is Primary { return ordinary }
    let prepared = []
    for item in ordinary {
      if item.candidates.is_empty() { prepared.push(item); continue }
      guard item.source.kind() is File(role) else { continue }
      if self.source_for(item.candidates, role, omit_selected=false) is Some(sources) {
        for source in sources { prepared.push({ source, candidates: item.candidates }) }
      }
    }
    return prepared
  }
  let sources = []
  for item in ordinary {
    if item.candidates.is_empty() { sources.push(item); continue }
    guard item.source.kind() is File(role) else { continue }
    let directories = []
    for path in item.candidates {
      if path.parent() is Some(dir) && !directories.contains(dir) { directories.push(dir) }
    }
    for group in layers.groups {
      if group.supplemental is Some(file) {
        let paths = directories.map(dir => dir.child(file.name))
        if self.source_for(paths, role, supplemental=file, omit_selected=false) is Some(stage) {
          for source in stage { sources.push({ source, candidates: paths }) }
        }
      }
      let paths = item.candidates.filter(path => path.name() is Some(name) && group.extensions.any(extension => name.has_suffix("." + extension.text)))
      if self.source_for(paths, role, omit_selected=false) is Some(stage) {
        for source in stage { sources.push({ source, candidates: paths }) }
      }
    }
  }
  sources
}
