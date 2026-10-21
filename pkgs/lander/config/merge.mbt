///|
/// Merge `overlay` over `base` with the default rules: a null overlay keeps the
/// base value, at any depth, and a null overlay field with no base field adds
/// nothing; two structs merge field by field, with base fields first and new
/// overlay fields after; in all other cases the overlay value wins, so a list
/// replaces a list. The inputs do not change, and unchanged subtrees are
/// shared.
pub fn merge(base : ConfigValue, overlay : ConfigValue) -> ConfigValue {
  if overlay.ion.is_null() {
    return base
  }
  guard base.ion.kind() is Struct(base_fields) &&
    overlay.ion.kind() is Struct(overlay_fields) else {
    overlay
  }
  let merged = base_fields.copy()
  for field in overlay_fields {
    // A null overlay field keeps the base field, or adds nothing.
    if field.value().is_null() {
      continue
    }
    // Field names always have text, so names compare by text.
    let name = field.name()
    match merged.search_by(existing => existing.name().text() == name.text()) {
      Some(index) => {
        let value = merge(
          { ion: merged[index].value() },
          { ion: field.value() },
        )
        merged[index] = @ion.Field::from_token(name, value.ion)
      }
      None => merged.push(field)
    }
  }
  // The result keeps the overlay annotations if it has any, else the base ones.
  let annotations = if overlay.ion.has_annotations() {
    overlay.ion.annotations()
  } else {
    base.ion.annotations()
  }
  { ion: @ion.Ion::from_fields(merged).with_annotations(annotations) }
}
