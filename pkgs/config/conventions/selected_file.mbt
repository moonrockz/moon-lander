///|
/// Overlay selection does not participate in the root/member decision.
fn Conventions::primary_options(self : Conventions, options : DiscoveryOptions) -> DiscoveryOptions {
  if self.selected_file is Overlay && options.config is Explicit(_) {
    { ..options, config: Discover }
  } else { options }
}

///|
fn Conventions::prepared_layers(self : Conventions) -> Bool {
  self.layers is Some(_) || self.selected_file is Overlay
}

///|
/// Exclude the selected physical identity before ordinary sources execute.
fn Scan::keep_source(self : Scan, path : @config.FileTreePath, source : @config.ConfigSource) -> Array[@config.ConfigSource] raise @config.ConfigError {
  if self.selected == Some(normalize(path)) { [] } else { [source] }
}

///|
fn Scan::overlay_origin(self : Scan, path : @config.FileTreePath) -> @config.Origin {
  { kind: File(Explicit), source: self.conventions.display, priority: 325, location: Some(path.to_string()) }
}

///|
/// Retain original base control metadata while authorizing the moved ordinary
/// source. A selected external/member file cannot gain that authority.
fn Scan::overlay_authority(self : Scan, resolution : @config.ProfileResolution) -> @config.ProfileResolution {
  guard self.selected is Some(path) else { return resolution }
  let origin = { ..self.overlay_origin(path), kind: File(Workspace), priority: 300 }
  if resolution.permits_controls(origin) {
    resolution.with_control_authority(self.overlay_origin(path))
  } else { resolution }
}

///|
fn Scan::with_selected_overlay(self : Scan, tier : Tier) -> Tier? raise @config.ConfigError {
  guard self.selected is Some(path) else { return Some(tier) }
  let value = match self.read_document(path) {
    Found(value) => value
    Missing => raise @config.FileNotFound(path=path.to_string())
    Unknown => return None
  }
  let as_member = tier.locations.any(location => location.1 && location.0 == path)
  let filters = if as_member { key_paths(self.conventions.member_scope) } else if tier.has_member { key_paths(self.conventions.inherited) } else { [] }
  let overlay = filtered(@config.ConfigSource::parsed_file(path.to_string(), value, role=Explicit, priority=325, name=self.conventions.display), filters, warn=as_member)
  let sources = []
  let mut inserted = false
  for source in tier.sources {
    if !inserted && !(source.kind() is File(Workspace | Legacy | Explicit)) {
      sources.push(overlay)
      inserted = true
    }
    sources.push(source)
  }
  if !inserted { sources.push(overlay) }
  Some({ ..tier, sources })
}
