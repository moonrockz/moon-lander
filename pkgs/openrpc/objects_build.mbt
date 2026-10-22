///|
fn uri_json(uri : @reference.UriReference) -> @exact.Value {
  @exact.Value::string(uri.text())
}

///|
fn[T] inline_json(
  value : InlineOrReference[T],
  encode : (T) -> @exact.Value,
) -> @exact.Value {
  match value {
    Inline(value) => encode(value)
    Reference(ref_) =>
      @exact.Value::object([("$ref", @exact.Value::string(ref_.text()))]).unwrap()
  }
}

///|
fn[T] add_optional(
  fields : Array[(String, @exact.Value)],
  name : String,
  value : T?,
  encode : (T) -> @exact.Value,
) -> Unit {
  if value is Some(value) {
    fields.push((name, encode(value)))
  }
}

///|
fn prefix_diagnostic(name : String, d : @exact.Diagnostic) -> @exact.Diagnostic {
  let path = [name]
  for part in d.path() {
    path.push(part)
  }
  @exact.Diagnostic::new(
    d.code(),
    d.message(),
    path~,
    span=d.span(),
    related=d.related(),
  )
}

///|
fn[T] add_dictionary(
  fields : Array[(String, @exact.Value)],
  name : String,
  entries : Array[(String, T)]?,
  encode : (T) -> @exact.Value,
) -> Result[Unit, @exact.Diagnostic] {
  if entries is Some(entries) {
    match
      @exact.Value::object(entries.map(entry => (entry.0, encode(entry.1)))) {
      Ok(value) => fields.push((name, value))
      Err(d) => return Err(prefix_diagnostic(name, d))
    }
  }
  Ok(())
}

///|
fn make_object(
  fields : Array[(String, @exact.Value)],
  kind : ObjectKind,
  extensions : Extensions,
  additional_fields : Array[(String, @exact.Value)],
) -> Result[@exact.Value, @exact.Diagnostic] {
  let known = field_names(kind)
  for (name, value) in additional_fields {
    if known.contains(name) || name.has_prefix("x-") {
      return Err(
        @exact.Diagnostic::new(
          @exact.WrongType,
          "Known fields and extensions require their typed inputs",
          path=[name],
        ),
      )
    }
    fields.push((name, value))
  }
  for (name, value) in extensions.entries() {
    fields.push((name.to_string(), value))
  }
  @exact.Value::object(fields)
}

///|
pub fn Contact::new(
  name~ : String? = None,
  url~ : @reference.UriReference? = None,
  email~ : String? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Contact, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  add_optional(fields, "name", name, @exact.Value::string)
  add_optional(fields, "url", url, uri_json)
  add_optional(fields, "email", email, @exact.Value::string)
  match make_object(fields, ContactObject, extensions, additional_fields) {
    Ok(value) => Contact::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn License::new(
  name~ : String? = None,
  url~ : @reference.UriReference? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[License, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  add_optional(fields, "name", name, @exact.Value::string)
  add_optional(fields, "url", url, uri_json)
  match make_object(fields, LicenseObject, extensions, additional_fields) {
    Ok(value) => License::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn ExternalDocumentation::new(
  url : @reference.UriReference,
  description~ : String? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ExternalDocumentation, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("url", uri_json(url)))
  add_optional(fields, "description", description, @exact.Value::string)
  match
    make_object(
      fields,
      ExternalDocumentationObject,
      extensions,
      additional_fields,
    ) {
    Ok(value) => ExternalDocumentation::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn ServerVariable::new(
  default_value : String,
  enum_values~ : Array[String]? = None,
  description~ : String? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ServerVariable, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("default", @exact.Value::string(default_value)))
  add_optional(fields, "enum", enum_values, fn(v) {
    @exact.Value::array(v.map(name => @exact.Value::string(name)))
  })
  add_optional(fields, "description", description, @exact.Value::string)
  match
    make_object(fields, ServerVariableObject, extensions, additional_fields) {
    Ok(value) => ServerVariable::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn Server::new(
  url : String,
  name~ : String? = None,
  summary~ : String? = None,
  description~ : String? = None,
  variables~ : Array[(String, ServerVariable)]? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Server, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("url", @exact.Value::string(url)))
  add_optional(fields, "name", name, @exact.Value::string)
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  match
    add_dictionary(fields, "variables", variables, ServerVariable::to_json) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  match make_object(fields, ServerObject, extensions, additional_fields) {
    Ok(value) => Server::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn Tag::new(
  name : String,
  summary~ : String? = None,
  description~ : String? = None,
  external_docs~ : ExternalDocumentation? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Tag, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("name", @exact.Value::string(name)))
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  add_optional(
    fields,
    "externalDocs",
    external_docs,
    ExternalDocumentation::to_json,
  )
  match make_object(fields, TagObject, extensions, additional_fields) {
    Ok(value) => Tag::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn ErrorObject::new(
  code : ErrorCode,
  message : String,
  data~ : @exact.Value? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ErrorObject, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("code", @exact.Value::number(code.number())))
  fields.push(("message", @exact.Value::string(message)))
  add_optional(fields, "data", data, fn(v) { v })
  match make_object(fields, ErrorObjectKind, extensions, additional_fields) {
    Ok(value) => ErrorObject::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn Example::new(
  payload : ExampleValue,
  name~ : String? = None,
  summary~ : String? = None,
  description~ : String? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Example, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  match payload {
    NoExampleValue => ()
    LiteralExample(value) => fields.push(("value", value))
    ExternalExample(uri) => fields.push(("externalValue", uri_json(uri)))
  }
  add_optional(fields, "name", name, @exact.Value::string)
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  match make_object(fields, ExampleObject, extensions, additional_fields) {
    Ok(value) => Example::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn ExamplePairing::new(
  name : String,
  params : Array[InlineOrReference[Example]],
  summary~ : String? = None,
  description~ : String? = None,
  result~ : InlineOrReference[Example]? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ExamplePairing, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("name", @exact.Value::string(name)))
  fields.push(
    (
      "params",
      @exact.Value::array(
        params.map(item => inline_json(item, Example::to_json)),
      ),
    ),
  )
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  add_optional(fields, "result", result, fn(v) {
    inline_json(v, Example::to_json)
  })
  match
    make_object(fields, ExamplePairingObject, extensions, additional_fields) {
    Ok(value) => ExamplePairing::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn Link::new(
  name~ : String? = None,
  summary~ : String? = None,
  description~ : String? = None,
  target_method~ : MethodName? = None,
  params~ : Array[(String, @exact.Value)]? = None,
  server~ : Server? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Link, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  add_optional(fields, "name", name, @exact.Value::string)
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  add_optional(fields, "method", target_method, fn(v) {
    @exact.Value::string(v.to_string())
  })
  match add_dictionary(fields, "params", params, fn(v) { v }) {
    Ok(_) => ()
    Err(d) => return Err(d)
  }
  add_optional(fields, "server", server, Server::to_json)
  match make_object(fields, LinkObject, extensions, additional_fields) {
    Ok(value) => Link::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn Info::new(
  title : String,
  version : String,
  description~ : String? = None,
  terms_of_service~ : @reference.UriReference? = None,
  contact~ : Contact? = None,
  license~ : License? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Info, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("title", @exact.Value::string(title)))
  fields.push(("version", @exact.Value::string(version)))
  add_optional(fields, "description", description, @exact.Value::string)
  add_optional(fields, "termsOfService", terms_of_service, uri_json)
  add_optional(fields, "contact", contact, Contact::to_json)
  add_optional(fields, "license", license, License::to_json)
  match make_object(fields, InfoObject, extensions, additional_fields) {
    Ok(value) => Info::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn ContentDescriptor::new(
  name : String,
  schema : @schema.Schema,
  summary~ : String? = None,
  description~ : String? = None,
  required~ : Bool? = None,
  deprecated~ : Bool? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ContentDescriptor, @exact.Diagnostic] {
  let fields : Array[(String, @exact.Value)] = []
  fields.push(("name", @exact.Value::string(name)))
  fields.push(("schema", @schema.Schema::to_json(schema)))
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  add_optional(fields, "required", required, @exact.Value::boolean)
  add_optional(fields, "deprecated", deprecated, @exact.Value::boolean)
  match
    make_object(fields, ContentDescriptorObject, extensions, additional_fields) {
    Ok(value) => ContentDescriptor::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub fn ContentDescriptor::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ContentDescriptor, @exact.Diagnostic] {
  checked_object(value, limits, (v, path, limits) => {
    match descriptor(v, path, limits~) {
      Inline(value) => value
      Reference(_) =>
        raise DecodeError(
          @exact.Diagnostic::new(
            @exact.WrongType,
            "Expected an inline content descriptor",
            path~,
          ),
        )
    }
  })
}
