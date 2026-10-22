///|
fn[T] optional_array_(
  value : @exact.Value,
  name : String,
  path : Array[String],
  decode : (@exact.Value, Array[String], @exact.Limits) -> T raise DecodeError,
  limits~ : @exact.Limits,
) -> Array[T]? raise DecodeError {
  match value.get(name) {
    None => None
    Some(raw) => {
      let at = child(path, name)
      Some(
        array(raw, at).mapi((i, v) => {
          decode(v, child(at, i.to_string()), limits)
        }),
      )
    }
  }
}

///|
fn tag_ref(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> InlineOrReference[Tag] raise DecodeError {
  match reference(value, path, limits~) {
    Some(ref_) => Reference(ref_)
    None => Inline(tag_(value, path, limits))
  }
}

///|
fn error_ref(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> InlineOrReference[ErrorObject] raise DecodeError {
  match reference(value, path, limits~) {
    Some(ref_) => Reference(ref_)
    None => Inline(error_object_(value, path, limits))
  }
}

///|
fn link_ref(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> InlineOrReference[Link] raise DecodeError {
  match reference(value, path, limits~) {
    Some(ref_) => Reference(ref_)
    None => Inline(link_(value, path, limits))
  }
}

///|
fn pairing_ref(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> InlineOrReference[ExamplePairing] raise DecodeError {
  match reference(value, path, limits~) {
    Some(ref_) => Reference(ref_)
    None => Inline(pairing_(value, path, limits))
  }
}

///|
pub fn ParamStructure::to_string(self : ParamStructure) -> String {
  match self {
    ByName => "by-name"
    ByPosition => "by-position"
    Either => "either"
  }
}

///|
pub fn Document::schema(self : Document) -> @reference.UriReference? {
  self.schema_uri
}

///|
pub fn Document::servers(self : Document) -> Array[Server]? {
  self.servers.map(items => items.copy())
}

///|
pub fn Document::components(self : Document) -> Components? {
  self.components
}

///|
pub fn Document::external_docs(self : Document) -> ExternalDocumentation? {
  self.external_docs
}

///|
pub fn Document::extensions(self : Document) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Document::additional_fields(
  self : Document,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, DocumentObject)
}

///|
pub fn Document::new(
  version : DocumentVersion,
  info : Info,
  methods : Array[InlineOrReference[Method]],
  schema~ : @reference.UriReference? = None,
  servers~ : Array[Server]? = None,
  components~ : Components? = None,
  external_docs~ : ExternalDocumentation? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Document, Array[@exact.Diagnostic]] {
  let fields = [
    ("openrpc", @exact.Value::string(version.to_string())),
    ("info", info.to_json()),
    (
      "methods",
      @exact.Value::array(
        methods.map(item => inline_json(item, Method::to_json)),
      ),
    ),
  ]
  add_optional(fields, "$schema", schema, uri_json)
  add_optional(fields, "servers", servers, v => {
    @exact.Value::array(v.map(Server::to_json))
  })
  add_optional(fields, "components", components, Components::to_json)
  add_optional(
    fields,
    "externalDocs",
    external_docs,
    ExternalDocumentation::to_json,
  )
  match make_object(fields, DocumentObject, extensions, additional_fields) {
    Ok(value) => Document::from_json(value, limits~)
    Err(d) => Err([d])
  }
}

///|
pub fn Method::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Method, @exact.Diagnostic] {
  checked_object(value, limits, (v, p, limits) => {
    match method_(v, p, limits~) {
      Inline(value) => value
      Reference(_) =>
        raise DecodeError(
          @exact.Diagnostic::new(
            @exact.WrongType,
            "Expected an inline method",
            path=p,
          ),
        )
    }
  })
}

///|
pub fn Method::summary(self : Method) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn Method::description(self : Method) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn Method::deprecated(self : Method) -> Bool? {
  opt_bool(self.value, "deprecated")
}

///|
pub fn Method::external_docs(self : Method) -> ExternalDocumentation? {
  self.value.get("externalDocs").map(v => ExternalDocumentation::{ value: v, })
}

///|
pub fn Method::servers(self : Method) -> Array[Server]? {
  self.value
  .get("servers")
  .map(v => value_array(v).map(v => Server::{ value: v, }))
}

///|
pub fn Method::tags(self : Method) -> Array[InlineOrReference[Tag]]? {
  self.value
  .get("tags")
  .map(v => value_array(v).map(v => reference_view(v, v => Tag::{ value: v, })))
}

///|
pub fn Method::errors(self : Method) -> Array[InlineOrReference[ErrorObject]]? {
  self.value
  .get("errors")
  .map(v => {
    value_array(v).map(v => reference_view(v, v => ErrorObject::{ value: v, }))
  })
}

///|
pub fn Method::links(self : Method) -> Array[InlineOrReference[Link]]? {
  self.value
  .get("links")
  .map(v => value_array(v).map(v => reference_view(v, v => Link::{ value: v, })))
}

///|
pub fn Method::examples(
  self : Method,
) -> Array[InlineOrReference[ExamplePairing]]? {
  self.value
  .get("examples")
  .map(v => {
    value_array(v).map(v => {
      reference_view(v, v => ExamplePairing::{ value: v, })
    })
  })
}

///|
pub fn Method::extensions(self : Method) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Method::additional_fields(
  self : Method,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, MethodObject)
}

///|
pub fn Method::new(
  name : MethodName,
  params : Array[InlineOrReference[ContentDescriptor]],
  result~ : InlineOrReference[ContentDescriptor]? = None,
  tags~ : Array[InlineOrReference[Tag]]? = None,
  summary~ : String? = None,
  description~ : String? = None,
  external_docs~ : ExternalDocumentation? = None,
  deprecated~ : Bool? = None,
  servers~ : Array[Server]? = None,
  errors~ : Array[InlineOrReference[ErrorObject]]? = None,
  links~ : Array[InlineOrReference[Link]]? = None,
  param_structure~ : ParamStructure? = None,
  examples~ : Array[InlineOrReference[ExamplePairing]]? = None,
  extensions~ : Extensions = Extensions::empty(),
  additional_fields~ : Array[(String, @exact.Value)] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Method, @exact.Diagnostic] {
  let fields = [
    ("name", @exact.Value::string(name.to_string())),
    (
      "params",
      @exact.Value::array(
        params.map(item => inline_json(item, ContentDescriptor::to_json)),
      ),
    ),
  ]
  add_optional(fields, "result", result, v => {
    inline_json(v, ContentDescriptor::to_json)
  })
  add_optional(fields, "tags", tags, v => {
    @exact.Value::array(v.map(item => inline_json(item, Tag::to_json)))
  })
  add_optional(fields, "summary", summary, @exact.Value::string)
  add_optional(fields, "description", description, @exact.Value::string)
  add_optional(
    fields,
    "externalDocs",
    external_docs,
    ExternalDocumentation::to_json,
  )
  add_optional(fields, "deprecated", deprecated, @exact.Value::boolean)
  add_optional(fields, "servers", servers, v => {
    @exact.Value::array(v.map(Server::to_json))
  })
  add_optional(fields, "errors", errors, v => {
    @exact.Value::array(v.map(item => inline_json(item, ErrorObject::to_json)))
  })
  add_optional(fields, "links", links, v => {
    @exact.Value::array(v.map(item => inline_json(item, Link::to_json)))
  })
  add_optional(fields, "paramStructure", param_structure, v => {
    @exact.Value::string(v.to_string())
  })
  add_optional(fields, "examples", examples, v => {
    @exact.Value::array(
      v.map(item => inline_json(item, ExamplePairing::to_json)),
    )
  })
  match make_object(fields, MethodObject, extensions, additional_fields) {
    Ok(value) => Method::from_json(value, limits~)
    Err(d) => Err(d)
  }
}
