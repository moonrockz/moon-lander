///|
/// The leaves of the struct `value` with their key paths, in tree order. A
/// leaf is a value below a struct field that is not a struct; a list counts as
/// one leaf. Null fields are not leaves.
fn leaves(value : ConfigValue) -> Array[(KeyPath, ConfigValue)] {
  let out = []
  fn walk(ion : @ion.Ion, names : Array[String]) {
    guard ion.kind() is Struct(fields) else { return }
    for field in fields {
      let value = field.value()
      guard field.name().text() is Some(name) && !value.is_null() else {
        continue
      }
      let path = [..names, name]
      if value.kind() is Struct(_) {
        walk(value, path)
      } else {
        out.push(({ names: path }, { ion: value }))
      }
    }
  }
  walk(value.ion, [])
  out
}

///|
/// Record `origin` for each leaf of `tree`. A new leaf removes the records at,
/// below, and above its path, then adds its own.
fn record_origins(
  provenance : Map[KeyPath, Array[Origin]],
  tree : ConfigValue,
  origin : Origin,
) -> Unit {
  for leaf in leaves(tree) {
    let (path, _) = leaf
    let stale = provenance
      .keys()
      .filter(key => is_prefix(key, path) || is_prefix(path, key))
      .collect()
    for key in stale {
      provenance.remove(key)
    }
    provenance[path] = [origin]
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
