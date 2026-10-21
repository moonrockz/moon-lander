///|
/// How two lists merge at one key path. The default is `Replace`. A key-path
/// policy beats the source policy.
pub(all) enum MergePolicy {
  Replace
  Append
  MergeByKey(String)
} derive(Eq, Debug)

///|
pub extend MergePolicy with Eq::{equal, not_equal}

///|
pub extend MergePolicy with @debug.Debug::{to_repr}

///|
pub impl Show for MergePolicy with output(self, logger) {
  match self {
    Replace => logger.write_string("Replace")
    Append => logger.write_string("Append")
    MergeByKey(name) => logger.write_string("MergeByKey(\{name})")
  }
}

///|
pub extend MergePolicy with Show::{output, to_string}

///|
/// The policy that applies at `path`: a key-path policy when one matches,
/// else the source policy.
fn resolve_policy(
  path : Array[String],
  source_policy : MergePolicy,
  key_policies : Array[(KeyPath, MergePolicy)],
) -> MergePolicy {
  for entry in key_policies {
    let (key, policy) = entry
    if key.names == path {
      return policy
    }
  }
  source_policy
}
