///|
/// A nonempty file extension, without a dot or path separator.
pub struct Extension {
  priv text : String
} derive(Eq, Hash, Debug)

///|
pub extend Extension with Eq::{equal, not_equal}

///|
pub extend Extension with Hash::{hash, hash_combine}

///|
pub extend Extension with @debug.Debug::{to_repr}

///|
/// Parse ASCII letters, digits, underscores and hyphens. Case is preserved
/// and must match a registered format's extension.
pub fn Extension::parse(text : String) -> Extension raise @config.ConfigError {
  guard !text.is_empty() else {
    raise @config.ConventionPolicy(input=text, rule=EmptyExtension)
  }
  guard text.iter().all(char => char.is_ascii_alphabetic() || char.is_ascii_digit() || char is ('_' | '-')) else {
    raise @config.ConventionPolicy(input=text, rule=ExtensionCharacters)
  }
  { text, }
}

///|
/// The extension without a dot.
pub fn Extension::to_string(self : Extension) -> String { self.text }

///|
/// One application-owned source below the ordinary primary of its format
/// group. Its transform must be pure. Discovery reuses its parsed value for
/// classification and the final source, rather than running it twice.
pub struct SupplementalFile {
  priv name : String
  priv extension : Extension
  priv transform : (@config.ConfigValue) -> @config.ConfigValue raise @config.ConfigError
}

///|
/// Parse one file name with a declared extension. Paths, . and .. are refused.
pub fn SupplementalFile::new(
  name : String,
  extension : Extension,
  transform? : (@config.ConfigValue) -> @config.ConfigValue raise @config.ConfigError = value => value,
) -> SupplementalFile raise @config.ConfigError {
  guard !name.is_empty() && name != "." && name != ".." &&
    !name.iter().any(char => char is ('/' | '\\' | '\u{0}')) else {
    raise @config.ConventionPolicy(input=name, rule=SupplementalName)
  }
  guard name.has_suffix("." + extension.text) else {
    raise @config.ConventionPolicy(input=name, rule=SupplementalExtension)
  }
  { name, extension, transform }
}

///|
/// The validated file name.
pub fn SupplementalFile::name(self : SupplementalFile) -> String { self.name }

///|
/// Alternatives at one precedence step. At most one ordinary candidate may
/// exist across these extensions and layouts. A supplemental source is below it.
pub struct FormatGroup {
  priv extensions : Array[Extension]
  priv supplemental : SupplementalFile?
}

///|
/// Make a nonempty group with unique extensions. Its optional supplemental
/// source must use one of those extensions.
pub fn FormatGroup::new(
  extensions : Array[Extension],
  supplemental? : SupplementalFile,
) -> FormatGroup raise @config.ConfigError {
  guard !extensions.is_empty() else {
    raise @config.ConventionPolicy(input="format group", rule=EmptyFormatGroup)
  }
  let seen : @hashset.HashSet[Extension] = @hashset.HashSet([])
  for extension in extensions {
    if seen.contains(extension) {
      raise @config.ConventionPolicy(input=extension.text, rule=DuplicateExtension)
    }
    seen.add(extension)
  }
  if supplemental is Some(file) && !seen.contains(file.extension) {
    raise @config.ConventionPolicy(input=file.name, rule=SupplementalOutsideGroup)
  }
  { extensions: extensions.copy(), supplemental }
}

///|
/// A copy of the alternatives in this group.
pub fn FormatGroup::extensions(self : FormatGroup) -> Array[Extension] {
  self.extensions.copy()
}

///|
/// Explicit precedence order with each extension in one group. Later groups
/// win shared keys. Parser registration order does not select precedence.
pub struct FormatLayers {
  priv groups : Array[FormatGroup]
}

///|
/// Make a nonempty order. Repeated extensions, also across groups, are refused.
pub fn FormatLayers::new(groups : Array[FormatGroup]) -> FormatLayers raise @config.ConfigError {
  guard !groups.is_empty() else {
    raise @config.ConventionPolicy(input="format order", rule=EmptyFormatOrder)
  }
  let seen : @hashset.HashSet[Extension] = @hashset.HashSet([])
  for group in groups {
    for extension in group.extensions {
      if seen.contains(extension) {
        raise @config.ConventionPolicy(input=extension.text, rule=DuplicateExtension)
      }
      seen.add(extension)
    }
  }
  { groups: groups.copy() }
}

///|
/// Select ordered format layers. Omitting this step keeps the existing
/// cross-format ambiguity rule. Every extension must have a registered parser.
pub fn format_layers(conventions : Conventions, layers : FormatLayers) -> Conventions {
  { ..conventions, layers: Some(layers) }
}

///|
/// Check final parser availability before the discovery pass requests data.
fn Conventions::check_formats(self : Conventions, formats : Array[@config.Format]) -> Unit raise @config.ConfigError {
  guard self.layers is Some(layers) else { return }
  let registered = searched_extensions(formats)
  for group in layers.groups {
    if group.supplemental is Some(file) &&
      (self.has(Layouts) || self.has(SystemDir) || self.has(UserConfigDir) || self.has(AppHome)) &&
      file.name == "\{self.name}.\{file.extension.text}" {
      raise @config.ConventionPolicy(input=file.name, rule=SupplementalPrimaryCollision)
    }
    for extension in group.extensions {
      if !registered.contains(extension.text) {
        raise @config.ConventionPolicy(input=extension.text, rule=UnregisteredExtension)
      }
    }
  }
}
