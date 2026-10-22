///|
pub struct Components {
  value : @exact.Value
  schemas : Array[(ComponentKey, @schema.Schema)]?
  content_descriptors : Array[(ComponentKey, ContentDescriptor)]?
  examples : Array[(ComponentKey, Example)]?
  links : Array[(ComponentKey, Link)]?
  errors : Array[(ComponentKey, ErrorObject)]?
  tags : Array[(ComponentKey, Tag)]?
  example_pairings : Array[(ComponentKey, ExamplePairing)]?
  example_pairing_objects : Array[(ComponentKey, ExamplePairing)]?
} derive(Debug)

///|
pub fn Components::to_json(self : Components) -> @exact.Value {
  self.value
}

///|
pub fn Components::extensions(self : Components) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Components::additional_fields(
  self : Components,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ComponentsObject)
}

///|
pub fn Components::schemas(
  self : Components,
) -> Array[(ComponentKey, @schema.Schema)]? {
  self.schemas.map(entries => entries.copy())
}

///|
pub fn Components::content_descriptors(
  self : Components,
) -> Array[(ComponentKey, ContentDescriptor)]? {
  self.content_descriptors.map(entries => entries.copy())
}

///|
pub fn Components::examples(
  self : Components,
) -> Array[(ComponentKey, Example)]? {
  self.examples.map(entries => entries.copy())
}

///|
pub fn Components::links(self : Components) -> Array[(ComponentKey, Link)]? {
  self.links.map(entries => entries.copy())
}

///|
pub fn Components::errors(
  self : Components,
) -> Array[(ComponentKey, ErrorObject)]? {
  self.errors.map(entries => entries.copy())
}

///|
pub fn Components::tags(self : Components) -> Array[(ComponentKey, Tag)]? {
  self.tags.map(entries => entries.copy())
}

///|
pub fn Components::example_pairings(
  self : Components,
) -> Array[(ComponentKey, ExamplePairing)]? {
  self.example_pairings.map(entries => entries.copy())
}

///|
pub fn Components::example_pairing_objects(
  self : Components,
) -> Array[(ComponentKey, ExamplePairing)]? {
  self.example_pairing_objects.map(entries => entries.copy())
}

///|
fn[T] component_entries(
  value : @exact.Value,
  name : String,
  path : Array[String],
  decode : (@exact.Value, Array[String], @exact.Limits) -> T raise DecodeError,
  limits~ : @exact.Limits,
) -> Array[(ComponentKey, T)]? raise DecodeError {
  guard value.get(name) is Some(raw) else { return None }
  let at = child(path, name)
  Some(
    object(raw, at).map(entry => {
      let key_path = child(at, entry.0)
      let key = match ComponentKey::parse(entry.0) {
        Ok(key) => key
        Err(d) =>
          raise DecodeError(
            @exact.Diagnostic::new(d.code(), d.message(), path=key_path),
          )
      }
      (key, decode(entry.1, key_path, limits))
    }),
  )
}

///|
fn components_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Components raise DecodeError {
  object(value, path) |> ignore
  let schemas = component_entries(
    value,
    "schemas",
    path,
    (v, p, limits) => {
      match @schema.Schema::from_json(v, limits~) {
        Ok(schema) => schema
        Err(d) => {
          let at = p.copy()
          for part in d.path() {
            at.push(part)
          }
          raise DecodeError(
            @exact.Diagnostic::new(d.code(), d.message(), path=at),
          )
        }
      }
    },
    limits~,
  )
  let content_descriptors = component_entries(
    value,
    "contentDescriptors",
    path,
    (v, p, limits) => {
      match descriptor(v, p, limits~) {
        Inline(d) => d
        Reference(_) =>
          raise DecodeError(
            @exact.Diagnostic::new(
              @exact.WrongType,
              "Expected an inline reusable content descriptor",
              path=p,
            ),
          )
      }
    },
    limits~,
  )
  let examples = component_entries(value, "examples", path, example_, limits~)
  let links = component_entries(value, "links", path, link_, limits~)
  let errors = component_entries(value, "errors", path, error_object_, limits~)
  let tags = component_entries(value, "tags", path, tag_, limits~)
  let example_pairings = component_entries(
    value,
    "examplePairings",
    path,
    pairing_,
    limits~,
  )
  let example_pairing_objects = component_entries(
    value,
    "examplePairingObjects",
    path,
    pairing_,
    limits~,
  )
  {
    value,
    schemas,
    content_descriptors,
    examples,
    links,
    errors,
    tags,
    example_pairings,
    example_pairing_objects,
  }
}

///|
pub fn Components::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Components, @exact.Diagnostic] {
  checked_object(value, limits, (v, p, limits) => components_(v, p, limits))
}

///|
fn[T] add_component_table(
  fields : Array[(String, @exact.Value)],
  name : String,
  entries : Array[(ComponentKey, T)]?,
  encode : (T) -> @exact.Value,
) -> Result[Unit, @exact.Diagnostic] {
  if entries is Some(entries) {
    match
      @exact.Value::object(
        entries.map(entry => (entry.0.to_string(), encode(entry.1))),
      ) {
      Ok(value) => fields.push((name, value))
      Err(d) => return Err(prefix_diagnostic(name, d))
    }
  }
  Ok(())
}

///|
pub fn Components::new(
  schemas~ : Array[(ComponentKey, @schema.Schema)]? = None,
  content_descriptors~ : Array[(ComponentKey, ContentDescriptor)]? = None,
  examples~ : Array[(ComponentKey, Example)]? = None,
  links~ : Array[(ComponentKey, Link)]? = None,
  errors~ : Array[(ComponentKey, ErrorObject)]? = None,
  tags~ : Array[(ComponentKey, Tag)]? = None,
  example_pairings~ : Array[(ComponentKey, ExamplePairing)]? = None,
  example_pairing_objects~ : Array[(ComponentKey, ExamplePairing)]? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Components, @exact.Diagnostic] {
  let fields = []
  match
    add_component_table(fields, "schemas", schemas, @schema.Schema::to_json) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match
    add_component_table(
      fields,
      "contentDescriptors",
      content_descriptors,
      ContentDescriptor::to_json,
    ) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match add_component_table(fields, "examples", examples, Example::to_json) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match add_component_table(fields, "links", links, Link::to_json) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match add_component_table(fields, "errors", errors, ErrorObject::to_json) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match add_component_table(fields, "tags", tags, Tag::to_json) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match
    add_component_table(
      fields,
      "examplePairings",
      example_pairings,
      ExamplePairing::to_json,
    ) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match
    add_component_table(
      fields,
      "examplePairingObjects",
      example_pairing_objects,
      ExamplePairing::to_json,
    ) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match make_object(fields, ComponentsObject, extensions, additional_fields) {
    Ok(value) => Components::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub extend Components with @debug.Debug::{to_repr}
