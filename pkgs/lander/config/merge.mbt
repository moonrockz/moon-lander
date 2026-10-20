///|
/// Merge `overlay` over `base` with the default rules: two structs merge field
/// by field, with base fields first and new overlay fields after; in all other
/// cases the overlay value wins, so a list replaces a list. The inputs do not
/// change.
pub fn merge(base : ConfigValue, overlay : ConfigValue) -> ConfigValue {
  guard base.ion.kind() is Struct(base_fields) &&
    overlay.ion.kind() is Struct(overlay_fields) else {
    overlay
  }
  let merged = base_fields.copy()
  for field in overlay_fields {
    let name = field.name()
    match merged.search_by(existing => existing.name() == name) {
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
