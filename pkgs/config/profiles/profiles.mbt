///|
/// An immutable profile policy. Fallback roots and includes have no implicit
/// names. Groups are checked at construction and again as one effective graph.
pub struct Policy {
  priv fallback : @config.ProfileNames
  priv includes : @config.ProfileNames
  priv groups : Array[Group]
}

///|
priv struct Group {
  name : @config.ProfileName
  members : @config.ProfileNames
  origin : @config.ProfileOrigin
}

///|
/// Enable profile processing with no implicit default profile.
pub fn Policy::new() -> Policy {
  { fallback: @config.ProfileNames::new([]), includes: @config.ProfileNames::new([]), groups: [] }
}

///|
/// Set the fallback roots, used only when no higher selector is present.
pub fn fallback(policy : Policy, names : @config.ProfileNames) -> Policy {
  { ..policy, fallback: names }
}

///|
/// Set the policy includes, which precede file includes and selected roots.
pub fn includes(policy : Policy, names : @config.ProfileNames) -> Policy {
  { ..policy, includes: names }
}

///|
/// Define or replace one group. At most 64 groups with 64 members each are
/// permitted. The complete effective graph is checked during resolution.
pub fn group(policy : Policy, name : @config.ProfileName, members : @config.ProfileNames) -> Policy raise @config.ConfigError {
  let definition : Group = { name, members, origin: Policy }
  check_members(definition)
  let groups = policy.groups.filter(existing => existing.name != name)
  groups.push(definition)
  check_group_count(groups)
  { ..policy, groups }
}

///|
priv struct Controls {
  active : @config.ProfileNames?
  defaults : @config.ProfileNames?
  includes : @config.ProfileNames
  groups : Array[Group]
  origins : Array[@config.ProfileOrigin]
  source : @config.Origin?
}

///|
fn empty_controls() -> Controls {
  { active: None, defaults: None, includes: @config.ProfileNames::new([]), groups: [], origins: [], source: None }
}

///|
/// Resolve one immutable activation state. `variable` is a present selector
/// variable's name and value. `controls` is the authoritative base root and
/// its origin. Disabled selections never interpret controls or group graphs.
pub fn resolve(policy : Policy, selection : @config.ProfileSelection, variable? : (String, String), controls? : (@config.ConfigValue, @config.Origin)) -> @config.ProfileResolution raise @config.ConfigError {
  resolve_input(policy, SelectionInput::new(selection, variable?), controls?)
}

///|
/// A parsed selection boundary with its winning source. Preparing it lets
/// discovery decide whether it may read controls without parsing names again.
pub struct SelectionInput {
  priv selection : @config.ProfileSelection
  priv selected_by : @config.ProfileSelector
}

///|
/// Parse a present variable only when the explicit selection is Unspecified.
pub fn SelectionInput::new(selection : @config.ProfileSelection, variable? : (String, String)) -> SelectionInput raise @config.ConfigError {
  let (selection, selected_by) = match (selection, variable) {
    (Unspecified, Some((name, text))) => (@config.ProfileSelection::from_variable(text, variable=name), @config.ProfileSelector::Variable(name))
    (Unspecified, None) => (selection, @config.ProfileSelector::Fallback)
    _ => (selection, @config.ProfileSelector::Discovery)
  }
  { selection, selected_by }
}

///|
/// Whether discovery must suppress control interpretation and profile reads.
pub fn SelectionInput::disabled(self : SelectionInput) -> Bool {
  self.selection is Disabled
}

///|
/// Resolve a prepared typed selection. This never reparses its selected names.
pub fn resolve_input(policy : Policy, input : SelectionInput, controls? : (@config.ConfigValue, @config.Origin)) -> @config.ProfileResolution raise @config.ConfigError {
  let selection = input.selection
  let selected_by = input.selected_by
  if selection is Disabled {
    let empty = @config.ProfileNames::new([])
    return @config.ProfileResolution::new(selected_by, empty, empty, disabled=true)
  }
  let controls = match controls {
    Some((root, origin)) => parse_controls(root, origin)
    None => empty_controls()
  }
  let (selector, roots, root_origin) = match selection {
    Selected(names) => (selected_by, names, selector_origin(selected_by))
    Unspecified => match (controls.active, controls.defaults, controls.source) {
      (Some(names), _, Some(origin)) => (@config.ProfileSelector::BaseActive(origin), names, @config.ProfileOrigin::Control(origin, @config.KeyPath::parse("profiles.active")))
      (None, Some(names), Some(origin)) => (@config.ProfileSelector::BaseDefault(origin), names, @config.ProfileOrigin::Control(origin, @config.KeyPath::parse("profiles.default")))
      _ => (@config.ProfileSelector::Fallback, policy.fallback, @config.ProfileOrigin::Policy)
    }
    Disabled => abort("disabled selection returned before control parsing")
  }
  let groups = policy.groups.filter(group => !controls.groups.any(replacement => replacement.name == group.name)) + controls.groups
  check_group_count(groups)
  let ordered = groups.copy()
  ordered.sort_by((left, right) => left.name.to_string().compare(right.name.to_string()))
  // Validate every definition, including inactive groups, in lexical order.
  let heights : Map[@config.ProfileName, Int] = Map([])
  for definition in ordered { ignore(group_height(definition, ordered, [], heights)) }
  let memo : Map[@config.ProfileName, Array[(@config.ProfileName, @config.ProfileReason)]] = Map([])
  let expanded : Array[(@config.ProfileName, @config.ProfileReason)] = []
  for name in policy.includes.names() {
    append_root(expanded, name, Include(name, Policy), ordered, memo)
  }
  for name in controls.includes.names() {
    let origin = match controls.source {
      Some(source) => @config.ProfileOrigin::Control(source, @config.KeyPath::parse("profiles.include"))
      None => Policy
    }
    append_root(expanded, name, Include(name, origin), ordered, memo)
  }
  for name in roots.names() { append_root(expanded, name, Root(name, root_origin), ordered, memo) }
  let resolved = keep_last(expanded)
  let failure_origin = resolved.get(128).map(item => match item.1 {
    Root(_, origin) | Include(_, origin) | GroupMember(_, _, origin) => origin
  }).unwrap_or(root_origin)
  @config.ProfileResolution::new(selector, roots, @config.ProfileNames::new(resolved.map(item => item.0)), reasons=resolved.map(item => item.1), controls=controls.origins, failure_origin~)
}

///|
fn selector_origin(selector : @config.ProfileSelector) -> @config.ProfileOrigin raise @config.ConfigError {
  match selector {
    Discovery => Discovery
    Variable(name) => Variable(name)
    BaseActive(origin) | BaseDefault(origin) => Control(origin, @config.KeyPath::parse("profiles"))
    Fallback => Policy
  }
}

///|
fn control_origin(origin : @config.Origin, names : Array[String]) -> @config.ProfileOrigin raise @config.ConfigError {
  Control(origin, @config.KeyPath::from_names(names))
}

///|
fn control_fail(input : String, rule : @config.ProfileRule, origin : @config.ProfileOrigin) -> @config.ConfigError {
  @config.ConfigError::Profile(failure=@config.ProfileFailure::new(input, rule, origin~))
}

///|
fn parse_names(value : @ion.Ion, origin : @config.ProfileOrigin) -> @config.ProfileNames raise @config.ConfigError {
  guard value.kind() is List(items) else { raise control_fail("profile name list", ExpectedList, origin) }
  let names = []
  for item in items {
    guard item.kind() is String(text) else { raise control_fail("profile name", ExpectedString, origin) }
    if text.contains("${") { raise control_fail(text, NonLiteral, origin) }
    names.push(@config.ProfileName::parse(text, origin~))
  }
  @config.ProfileNames::new(names)
}

///|
fn parse_controls(root : @config.ConfigValue, source : @config.Origin) -> Controls raise @config.ConfigError {
  guard root.to_ion().kind() is Struct(fields) else { return empty_controls() }
  let mut table : @ion.Ion? = None
  for field in fields { if field.name().text() == Some("profiles") { table = Some(field.value()) } }
  guard table is Some(table) else { return empty_controls() }
  let origin = control_origin(source, ["profiles"])
  guard table.kind() is Struct(fields) else { raise control_fail("profiles", ExpectedTable, origin) }
  let mut active = None
  let mut defaults = None
  let mut includes = @config.ProfileNames::new([])
  let groups : Array[Group] = []
  let origins : Array[@config.ProfileOrigin] = [origin]
  for field in fields {
    guard field.name().text() is Some(name) else { continue }
    let origin = control_origin(source, ["profiles", name])
    origins.push(origin)
    match name {
      "active" => active = Some(parse_names(field.value(), origin))
      "default" => defaults = Some(parse_names(field.value(), origin))
      "include" => includes = parse_names(field.value(), origin)
      "groups" => {
        guard field.value().kind() is Struct(definitions) else { raise control_fail("profiles.groups", ExpectedTable, origin) }
        let definitions = definitions.copy()
        definitions.sort_by((left, right) => left.name().text().unwrap_or("").compare(right.name().text().unwrap_or("")))
        for definition in definitions {
          guard definition.name().text() is Some(text) else { continue }
          let origin = control_origin(source, ["profiles", "groups", text])
          origins.push(origin)
          let group : Group = { name: @config.ProfileName::parse(text, origin~), members: parse_names(definition.value(), origin), origin }
          check_members(group)
          groups.push(group)
        }
      }
      _ => raise control_fail(name, UnknownField, origin)
    }
  }
  check_group_count(groups)
  { active, defaults, includes, groups, origins, source: Some(source) }
}

///|
fn check_members(group : Group) -> Unit raise @config.ConfigError {
  let count = group.members.names().length()
  if count > 64 { raise control_fail(group.name.to_string(), MemberLimit(count), group.origin) }
}

///|
fn check_group_count(groups : Array[Group]) -> Unit raise @config.ConfigError {
  if groups.length() > 64 {
    let origin = groups.last().map(group => group.origin).unwrap_or(@config.ProfileOrigin::Policy)
    raise control_fail("profiles.groups", GroupLimit(groups.length()), origin)
  }
}

///|
fn find_group(groups : Array[Group], name : @config.ProfileName) -> Group? {
  for group in groups { if group.name == name { return Some(group) } }
  None
}

///|
fn group_height(group : Group, groups : Array[Group], stack : Array[@config.ProfileName], memo : Map[@config.ProfileName, Int]) -> Int raise @config.ConfigError {
  if stack.contains(group.name) {
    let index = stack.search(group.name).unwrap_or(0)
    let cycle = @config.ProfileNames::new([..stack[index:].to_owned(), group.name])
    raise @config.ConfigError::Profile(failure=@config.ProfileFailure::new(group.name.to_string(), Cycle, origin=group.origin, cycle~))
  }
  if memo.get(group.name) is Some(height) { return height }
  let mut height = 1
  for child_name in group.members.names() {
    if find_group(groups, child_name) is Some(child) {
      height = height.max(1 + group_height(child, groups, [..stack, group.name], memo))
    }
  }
  if height > 32 { raise control_fail(group.name.to_string(), DepthLimit(height), group.origin) }
  memo[group.name] = height
  height
}

///|
fn append_root(output : Array[(@config.ProfileName, @config.ProfileReason)], name : @config.ProfileName, reason : @config.ProfileReason, groups : Array[Group], memo : Map[@config.ProfileName, Array[(@config.ProfileName, @config.ProfileReason)]]) -> Unit {
  output.push((name, reason))
  if find_group(groups, name) is Some(group) { output.append(expand_group(group, groups, memo)) }
  // Deduplicate after each root. Each array stays bounded by the definitions'
  // distinct names even for a diamond with exponentially many paths.
  let kept = keep_last(output)
  output.clear()
  output.append(kept)
}

///|
fn expand_group(group : Group, groups : Array[Group], memo : Map[@config.ProfileName, Array[(@config.ProfileName, @config.ProfileReason)]]) -> Array[(@config.ProfileName, @config.ProfileReason)] {
  if memo.get(group.name) is Some(expanded) { return expanded }
  let output = []
  for child_name in group.members.names() {
    append_root(output, child_name, GroupMember(child_name, group.name, group.origin), groups, memo)
  }
  memo[group.name] = output
  output
}

///|
fn keep_last(items : Array[(@config.ProfileName, @config.ProfileReason)]) -> Array[(@config.ProfileName, @config.ProfileReason)] {
  let seen : Set[@config.ProfileName] = Set([])
  let kept = []
  for item in items.rev() { if !seen.contains(item.0) { seen.add(item.0); kept.push(item) } }
  kept.rev()
}
