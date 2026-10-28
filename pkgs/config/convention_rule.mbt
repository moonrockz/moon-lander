///|
/// The construction and registration rules of an ordered format policy.
pub(all) enum ConventionRule {
  EmptyExtension
  ExtensionCharacters
  EmptyFormatGroup
  DuplicateExtension
  EmptyFormatOrder
  UnregisteredExtension
  SupplementalName
  SupplementalExtension
  SupplementalOutsideGroup
  SupplementalPrimaryCollision
} derive(Eq, Debug)

///|
pub extend ConventionRule with Eq::{equal, not_equal}

///|
pub extend ConventionRule with @debug.Debug::{to_repr}

///|
fn ConventionRule::description(self : ConventionRule) -> String {
  match self {
    EmptyExtension => "an extension must not be empty"
    ExtensionCharacters => "an extension must contain only ASCII letters, digits, underscores or hyphens"
    EmptyFormatGroup => "a format group needs at least one extension"
    DuplicateExtension => "an extension may occur in only one group and once in that group"
    EmptyFormatOrder => "a format order needs at least one group"
    UnregisteredExtension => "every ordered extension needs a registered parser"
    SupplementalName => "a supplemental source needs one file name, without separators, NUL, . or .."
    SupplementalExtension => "the supplemental file name must end with its declared extension"
    SupplementalOutsideGroup => "the supplemental extension must belong to its group"
    SupplementalPrimaryCollision => "a supplemental source must have a different identity from the ordinary primary"
  }
}
