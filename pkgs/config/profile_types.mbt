///|
/// A parsed lowercase ASCII profile name, from 1 to 64 characters. The first
/// character is a letter; later characters may also be digits, `_`, or `-`.
pub struct ProfileName {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend ProfileName with Eq::{equal, not_equal}

///|
pub extend ProfileName with Hash::{hash, hash_combine}

///|
pub extend ProfileName with @debug.Debug::{to_repr}

///|
/// Parse one profile name at its input boundary.
pub fn ProfileName::parse(text : String, origin? : ProfileOrigin = Policy) -> ProfileName raise ConfigError {
  if text.length() < 1 || text.length() > 64 {
    raise Profile(failure=ProfileFailure::new(text, NameLength(text.length()), origin~))
  }
  let chars = text.to_array()
  if !(chars[0] >= 'a' && chars[0] <= 'z') {
    raise Profile(failure=ProfileFailure::new(text, NameStart, origin~))
  }
  for char in chars {
    if !((char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char == '_' || char == '-') {
      raise Profile(failure=ProfileFailure::new(text, NameCharacter, origin~))
    }
  }
  { text, }
}

///|
/// The exact profile name as text.
pub impl Show for ProfileName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend ProfileName with Show::{output, to_string}

///|
/// An immutable ordered collection of parsed names. Repeats are retained.
pub struct ProfileNames {
  priv items : Array[ProfileName]
} derive(Eq, Debug)

///|
pub extend ProfileNames with Eq::{equal, not_equal}

///|
pub extend ProfileNames with @debug.Debug::{to_repr}

///|
/// Copy the supplied names into an immutable collection.
pub fn ProfileNames::new(names : Array[ProfileName]) -> ProfileNames {
  { items: names.copy() }
}

///|
/// A copy of the names in their original order.
pub fn ProfileNames::names(self : ProfileNames) -> Array[ProfileName] {
  self.items.copy()
}

///|
/// Whether the collection contains the parsed name.
pub fn ProfileNames::contains(self : ProfileNames, name : ProfileName) -> Bool {
  self.items.contains(name)
}

///|
/// An activation input. An explicit empty selection keeps includes; Disabled
/// suppresses all profile processing.
pub(all) enum ProfileSelection {
  Unspecified
  Selected(ProfileNames)
  Disabled
} derive(Eq, Debug)

///|
pub extend ProfileSelection with Eq::{equal, not_equal}

///|
pub extend ProfileSelection with @debug.Debug::{to_repr}

///|
/// The input boundary or literal control that supplied profile information.
pub(all) enum ProfileOrigin {
  Policy
  Discovery
  Variable(String)
  Control(Origin, KeyPath)
} derive(Eq, Debug)

///|
pub extend ProfileOrigin with Eq::{equal, not_equal}

///|
pub extend ProfileOrigin with @debug.Debug::{to_repr}

///|
/// The winning activation selector. File selectors retain their file origin.
pub(all) enum ProfileSelector {
  Discovery
  Variable(String)
  BaseActive(Origin)
  BaseDefault(Origin)
  Fallback
} derive(Eq, Debug)

///|
pub extend ProfileSelector with Eq::{equal, not_equal}

///|
pub extend ProfileSelector with @debug.Debug::{to_repr}

///|
/// Why a name appears in the final active order.
pub(all) enum ProfileReason {
  Root(ProfileName, ProfileOrigin)
  Include(ProfileName, ProfileOrigin)
  GroupMember(ProfileName, ProfileName, ProfileOrigin)
} derive(Eq, Debug)

///|
pub extend ProfileReason with Eq::{equal, not_equal}

///|
pub extend ProfileReason with @debug.Debug::{to_repr}

///|
/// A typed profile rule. Count failures retain the observed count.
pub(all) enum ProfileRule {
  NameLength(Int)
  NameStart
  NameCharacter
  EmptyElement
  ExpectedList
  ExpectedString
  ExpectedTable
  UnknownField
  NonLiteral
  ForbiddenLocation
  Cycle
  GroupLimit(Int)
  MemberLimit(Int)
  DepthLimit(Int)
  ActiveLimit(Int)
  CompetingProviders(String, String)
} derive(Eq, Debug)

///|
pub extend ProfileRule with Eq::{equal, not_equal}

///|
pub extend ProfileRule with @debug.Debug::{to_repr}

///|
/// A profile failure with its raw input, typed rule and input origin.
pub struct ProfileFailure {
  priv input : String
  priv rule : ProfileRule
  priv origin : ProfileOrigin
  priv cycle : ProfileNames
} derive(Eq, Debug)

///|
pub extend ProfileFailure with Eq::{equal, not_equal}

///|
pub extend ProfileFailure with @debug.Debug::{to_repr}

///|
/// Keep the evidence for a profile failure. A cycle holds its closed path.
pub fn ProfileFailure::new(input : String, rule : ProfileRule, origin? : ProfileOrigin = Policy, cycle? : ProfileNames = ProfileNames::new([])) -> ProfileFailure {
  { input, rule, origin, cycle }
}

///|
/// The raw name or control input that failed.
pub fn ProfileFailure::input(self : ProfileFailure) -> String { self.input }

///|
/// The rule that the input breaks.
pub fn ProfileFailure::rule(self : ProfileFailure) -> ProfileRule { self.rule }

///|
/// The boundary or control that supplied the input.
pub fn ProfileFailure::origin(self : ProfileFailure) -> ProfileOrigin { self.origin }

///|
/// The closed cycle path, or an empty collection for another failure.
pub fn ProfileFailure::cycle(self : ProfileFailure) -> ProfileNames { self.cycle }

///|
/// A human-readable failure. Programs can inspect the typed rule instead.
pub fn ProfileFailure::message(self : ProfileFailure) -> String {
  "Invalid profiles input \"\{self.input}\" at \{self.origin.to_repr()}: \{self.rule.to_repr()}"
}

///|
/// Immutable activation metadata retained only by a successful complete load.
pub struct ProfileResolution {
  priv selector : ProfileSelector
  priv roots : ProfileNames
  priv active : ProfileNames
  priv disabled : Bool
  priv reasons : Array[ProfileReason]
  priv controls : Array[ProfileOrigin]
  priv authorities : Array[Origin]
} derive(Eq, Debug)

///|
pub extend ProfileResolution with Eq::{equal, not_equal}

///|
pub extend ProfileResolution with @debug.Debug::{to_repr}

///|
/// Record a resolved ordered set. The active set has at most 128 distinct names.
/// Repeated active names keep their last occurrence. `failure_origin` identifies
/// the expansion input that first exceeds the active-name limit.
/// `authorities` names every eligible base source, including a base whose
/// controls a later base fully replaces. Existing callers derive that list
/// from `controls`. Winning control origins stay separate from eligibility.
pub fn ProfileResolution::new(selector : ProfileSelector, roots : ProfileNames, active : ProfileNames, disabled? : Bool = false, reasons? : Array[ProfileReason] = [], controls? : Array[ProfileOrigin] = [], authorities? : Array[Origin] = [], failure_origin? : ProfileOrigin) -> ProfileResolution raise ConfigError {
  let unique : Array[ProfileName] = []
  for name in active.items.rev() {
    if !unique.contains(name) { unique.push(name) }
  }
  if !disabled && unique.length() > 128 {
    let origin = failure_origin.unwrap_or_else(() => match selector {
      Discovery => ProfileOrigin::Discovery
      Variable(name) => ProfileOrigin::Variable(name)
      BaseActive(source) => ProfileOrigin::Control(source, KeyPath::{ names: ["profiles", "active"] })
      BaseDefault(source) => ProfileOrigin::Control(source, KeyPath::{ names: ["profiles", "default"] })
      Fallback => ProfileOrigin::Policy
    })
    raise Profile(failure=ProfileFailure::new("active profiles", ActiveLimit(unique.length()), origin~))
  }
  let eligible = authorities.copy()
  for control in controls {
    if control is Control(origin, _) && !eligible.contains(origin) { eligible.push(origin) }
  }
  { selector, roots: if disabled { ProfileNames::new([]) } else { roots }, active: ProfileNames::new(if disabled { [] } else { unique.rev() }), disabled, reasons: if disabled { [] } else { reasons.copy() }, controls: if disabled { [] } else { controls.copy() }, authorities: if disabled { [] } else { eligible } }
}

///|
/// The winning selection source.
pub fn ProfileResolution::selector(self : ProfileResolution) -> ProfileSelector { self.selector }

///|
/// The selected active or default roots, before group expansion.
pub fn ProfileResolution::roots(self : ProfileResolution) -> ProfileNames { self.roots }

///|
/// The final active names in merge order.
pub fn ProfileResolution::active(self : ProfileResolution) -> ProfileNames { self.active }

///|
/// Whether an explicit input disabled processing.
pub fn ProfileResolution::disabled(self : ProfileResolution) -> Bool { self.disabled }

///|
/// A defensive copy of the activation reasons.
pub fn ProfileResolution::reasons(self : ProfileResolution) -> Array[ProfileReason] { self.reasons.copy() }

///|
/// A defensive copy of the interpreted control origins.
pub fn ProfileResolution::controls(self : ProfileResolution) -> Array[ProfileOrigin] { self.controls.copy() }

///|
/// Whether this source is an eligible base control source. Authority is
/// separate from winning control origins, so fully overridden bases remain
/// eligible. Legacy constructors derive authority from their control origins.
pub fn ProfileResolution::permits_controls(self : ProfileResolution, origin : Origin) -> Bool { self.authorities.contains(origin) }

///|
/// Whether the parsed name is active.
pub fn ProfileResolution::contains(self : ProfileResolution, name : ProfileName) -> Bool { self.active.contains(name) }

///|
/// Off is different from an enabled policy whose active result is empty.
pub(all) enum ProfileState {
  Off
  Resolved(ProfileResolution)
} derive(Eq, Debug)

///|
pub extend ProfileState with Eq::{equal, not_equal}

///|
pub extend ProfileState with @debug.Debug::{to_repr}

///|
/// Whether the parsed name is active in this loaded state.
pub fn ProfileState::contains(self : ProfileState, name : ProfileName) -> Bool {
  match self { Off => false; Resolved(resolution) => resolution.contains(name) }
}

///|
/// Parse a comma-separated selector, trimming ASCII whitespace around names.
/// Empty names, including an empty whole selector, are an error.
pub fn ProfileNames::parse_csv(text : String, origin? : ProfileOrigin = Discovery) -> ProfileNames raise ConfigError {
  let names : Array[ProfileName] = []
  for part in text.split(",") {
    let name = profile_ascii_trim(part.to_owned())
    if name.is_empty() {
      raise Profile(failure=ProfileFailure::new(text, EmptyElement, origin~))
    }
    names.push(ProfileName::parse(name, origin~))
  }
  ProfileNames::new(names)
}

///|
/// Interpret a present selector variable. An empty or ASCII-whitespace-only
/// value disables profile processing; absence is handled as Unspecified.
pub fn ProfileSelection::from_variable(text : String, variable~ : String) -> ProfileSelection raise ConfigError {
  if profile_ascii_trim(text).is_empty() {
    Disabled
  } else {
    Selected(ProfileNames::parse_csv(text, origin=Variable(variable)))
  }
}

///|
fn profile_ascii_trim(text : String) -> String {
  text.trim(chars=" \t\n\r\u{000b}\u{000c}").to_owned()
}
