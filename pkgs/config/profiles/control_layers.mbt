///|
/// One eligible base document and its typed source origin. The document is
/// immutable and has an object root. Semantic controls are parsed only after
/// the ordered layers merge.
pub struct ControlLayer {
  priv root : @config.ConfigValue
  priv origin : @config.Origin
}

///|
/// Capture a base document. A non-object root raises the ordinary typed
/// configuration root error.
pub fn ControlLayer::new(value : @config.ConfigValue, origin : @config.Origin) -> ControlLayer raise @config.ConfigError {
  // Validate the source root without loading it. Ordinary config loading drops
  // null fields, but a null profile control must retain its typed shape error.
  ignore(@config.in_memory(value, name=origin.location.unwrap_or(origin.source)))
  { root: value, origin }
}

///|
/// An immutable merge of eligible base documents with original control
/// origins. Later layers win values and individual group definitions.
pub struct ControlLayers {
  priv layers : Array[ControlLayer]
  priv root : @config.ConfigValue
}

///|
/// Merge the layers without interpreting controls. An empty list is a valid
/// base with no controls. Caller arrays are copied.
pub fn ControlLayers::new(layers : Array[ControlLayer]) -> ControlLayers raise @config.ConfigError {
  let mut controls : @ion.Ion? = None
  for layer in layers {
    guard layer.root.to_ion().kind() is Struct(fields) else { continue }
    for field in fields {
      if field.name().text() == Some("profiles") {
        controls = Some(match controls {
          None => field.value()
          Some(previous) => merge_control_values(previous, field.value())
        })
      }
    }
  }
  let fields = controls.map(value => [@ion.field("profiles", value)]).unwrap_or([])
  let root = @config.ConfigValue::from_ion(@ion.Ion::from_fields(fields), origin="profile controls")
  { layers: layers.copy(), root }
}

///|
/// Reserved control values are literal metadata. Merge objects by field and
/// replace other values, including null, before their one semantic parse.
/// Ordinary configuration's null-as-unset rule must not hide a shape failure.
fn merge_control_values(base : @ion.Ion, overlay : @ion.Ion) -> @ion.Ion {
  match (base.kind(), overlay.kind()) {
    (Struct(left), Struct(right)) => {
      let fields = left.copy()
      for field in right {
        match fields.search_by(existing => existing.name().text() == field.name().text()) {
          Some(index) => fields[index] = @ion.Field::from_token(field.name(), merge_control_values(fields[index].value(), field.value()))
          None => fields.push(field)
        }
      }
      @ion.Ion::from_fields(fields).with_annotations(if overlay.has_annotations() { overlay.annotations() } else { base.annotations() })
    }
    _ => overlay
  }
}

///|
/// Containers, including empty objects, keep their declaring source as well
/// as leaves. Config's leaf-only provenance alone cannot recover those origins.
fn ControlLayers::origin(self : ControlLayers, names : Array[String]) -> @config.Origin {
  for layer in self.layers.rev() {
    if layer.contains(names) { return layer.origin }
  }
  // parse_controls asks only about paths present in the merged documents.
  // Merging cannot create a control that no input layer contains.
  abort("A present merged profile control must belong to an input layer")
}

///|
/// Inspect raw values so nulls and empty containers still count as present.
fn ControlLayer::contains(self : ControlLayer, names : Array[String]) -> Bool {
  let mut value = self.root.to_ion()
  for name in names {
    guard value.kind() is Struct(fields) else { return false }
    guard fields.iter().find_first(field => field.name().text() == Some(name)) is Some(field) else { return false }
    value = field.value()
  }
  true
}

///|
/// Resolve prepared activation against merged base controls. Every base stays
/// eligible even when a later base replaces all of its control values.
pub fn resolve_layers(policy : Policy, input : SelectionInput, layers : ControlLayers) -> @config.ProfileResolution raise @config.ConfigError {
  let controls = if input.disabled() { empty_controls() } else {
    parse_controls(layers.root, names => layers.origin(names))
  }
  resolve_prepared(policy, input, controls, authorities=layers.layers.map(layer => layer.origin))
}
