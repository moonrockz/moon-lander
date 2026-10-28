///|
/// Keep stage order outside format order: base primaries, member primaries,
/// then each adjacent stage, workspace before member within that stage.
fn Conventions::tier(self : Conventions, base : Layer, chosen : Layer?) -> Tier raise @config.ConfigError {
  let has_member = chosen is Some(_)
  let inherited = if has_member { key_paths(self.inherited) } else { [] }
  let scoped = if has_member { key_paths(self.member_scope) } else { [] }
  let sources = base.primaries.map(source => filtered(source, inherited, warn=false))
  if chosen is Some(chosen) {
    sources.append(chosen.primaries.map(source => filtered(source, scoped, warn=true)))
  }
  let count = base.adjacent.length().max(chosen.map(layer => layer.adjacent.length()).unwrap_or(0))
  for index in 0..<count {
    if base.adjacent.get(index) is Some(stage) {
      sources.append(stage.map(source => filtered(source, inherited, warn=false)))
    }
    if chosen is Some(chosen) && chosen.adjacent.get(index) is Some(stage) {
      sources.append(stage.map(source => filtered(source, scoped, warn=true)))
    }
  }
  let locations = base.paths.map(path => (path, false))
  if chosen is Some(chosen) {
    locations.append(chosen.paths.map(path => (path, true)))
  }
  { sources, has_member, locations, controls: base.controls }
}
