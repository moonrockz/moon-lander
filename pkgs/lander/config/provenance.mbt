///|
/// The leaves of the struct `value` with their key paths, in tree order. A
/// leaf is a value below a struct field that is not a struct; a list and a
/// secret reference each count as one leaf. Null fields are not leaves.
fn leaves(
  value : ConfigValue,
  secret_syntax~ : SecretSyntax = Standard,
) -> Array[(KeyPath, ConfigValue)] {
  let out = []
  fn walk(ion : @ion.Ion, names : Array[String]) {
    guard ion.kind() is Struct(fields) else { return }
    for field in fields {
      let value = field.value()
      guard field.name().text() is Some(name) && !value.is_null() else {
        continue
      }
      let path = [..names, name]
      let child = { ion: value }
      if is_secret_reference(child, secret_syntax) {
        out.push(({ names: path }, child))
      } else if value.kind() is Struct(_) {
        walk(value, path)
      } else {
        out.push(({ names: path }, child))
      }
    }
  }
  walk(value.ion, [])
  out
}

///|
/// Record `origin` for each leaf of `tree`. A new leaf removes the records at,
/// below, and above its path, then adds its own. An `Append` or `MergeByKey`
/// list keeps the origins that the path already has and adds `origin` after
/// them.
fn record_origins(
  provenance : Map[KeyPath, Array[Origin]],
  tree : ConfigValue,
  origin : Origin,
  source_policy~ : MergePolicy = Replace,
  key_policies~ : Array[(KeyPath, MergePolicy)] = [],
  secret_syntax~ : SecretSyntax = Standard,
  previous~ : ConfigValue = fields([]),
) -> Unit {
  for leaf in leaves(tree, secret_syntax~) {
    let (path, value) = leaf
    let policy = resolve_policy(path.names, source_policy, key_policies)
    // Append origins only when this overlay list merges with a base list.
    // A list that replaces a scalar (or a missing path) has one origin.
    let previous_was_list = match previous.at(path.names) {
      Some(prior) => prior.ion.kind() is List(_)
      None => false
    }
    let list_merge = match (value.ion.kind(), policy, previous_was_list) {
      (List(_), Append | MergeByKey(_), true) => true
      _ => false
    }
    let stale = provenance
      .keys()
      .filter(key => {
        if list_merge && key == path {
          false
        } else {
          is_prefix(key, path) || is_prefix(path, key)
        }
      })
      .collect()
    for key in stale {
      provenance.remove(key)
    }
    if list_merge {
      let existing = provenance.get(path).map(origins => origins.copy()).unwrap_or([])
      existing.push(origin)
      provenance[path] = existing
    } else {
      provenance[path] = [origin]
    }
  }
}

///|
/// Whether the names of `prefix` start the names of `path`.
fn is_prefix(prefix : KeyPath, path : KeyPath) -> Bool {
  prefix.names.length() <= path.names.length() &&
  prefix.names.iter().zip(path.names.iter()).all(pair => pair.0 == pair.1)
}

///|
/// `value` without struct fields whose value is null, at any depth, also in
/// structs inside lists. A null list item stays.
fn without_nulls(value : ConfigValue) -> ConfigValue {
  let ion = match value.ion.kind() {
    Struct(fields) => {
      let kept = []
      for field in fields {
        let child = field.value()
        if !child.is_null() {
          kept.push(
            @ion.Field::from_token(field.name(), without_nulls({ ion: child }).ion),
          )
        }
      }
      @ion.Ion::from_fields(kept)
    }
    List(items) =>
      @ion.Ion::list(items.map(item => without_nulls({ ion: item }).ion))
    Sexp(items) =>
      @ion.Ion::sexp(items.map(item => without_nulls({ ion: item }).ion))
    _ => return value
  }
  { ion: ion.with_annotations(value.ion.annotations()) }
}
