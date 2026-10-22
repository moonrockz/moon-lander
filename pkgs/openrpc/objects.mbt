///|
pub(all) enum ExampleValue {
  NoExampleValue
  LiteralExample(@exact.Value)
  ExternalExample(@reference.UriReference)
} derive(Debug)

///|
pub extend ExampleValue with @debug.Debug::{to_repr}

///|
fn value_fields(value : @exact.Value) -> Array[(String, @exact.Value)] {
  match value.kind() {
    @exact.Object(fields) => fields
    _ => abort("Object model invariant")
  }
}

///|
fn value_array(value : @exact.Value) -> Array[@exact.Value] {
  match value.kind() {
    @exact.Array(items) => items
    _ => abort("Array model invariant")
  }
}

///|
fn req_text(value : @exact.Value, name : String) -> String {
  value.get(name).unwrap().text().unwrap()
}

///|
fn opt_text(value : @exact.Value, name : String) -> String? {
  value.get(name).map(v => v.text().unwrap())
}

///|
fn opt_uri(value : @exact.Value, name : String) -> @reference.UriReference? {
  opt_text(value, name).map(v => {
    @reference.UriReference::parse(v, limits=@exact.Limits::unlimited()).unwrap()
  })
}

///|
fn opt_bool(value : @exact.Value, name : String) -> Bool? {
  value
  .get(name)
  .map(v => {
    match v.kind() {
      @exact.Boolean(b) => b
      _ => abort("Boolean model invariant")
    }
  })
}

///|
fn code_value(value : @exact.Value) -> ErrorCode {
  match value.kind() {
    @exact.Numeric(n) => ErrorCode::from_number(n).unwrap()
    _ => abort("Error code model invariant")
  }
}

///|
fn extensions_of(value : @exact.Value) -> Extensions {
  Extensions::from_json(
    @exact.Value::object(
      value_fields(value).filter(entry => entry.0.has_prefix("x-")),
    ).unwrap(),
  ).unwrap()
}

///|
fn extras_of(
  value : @exact.Value,
  kind : ObjectKind,
) -> Array[(String, @exact.Value)] {
  let known = field_names(kind)
  value_fields(value).filter(entry => {
    !known.contains(entry.0) && !entry.0.has_prefix("x-")
  })
}

///|
fn[T] reference_view(
  value : @exact.Value,
  wrap : (@exact.Value) -> T,
) -> InlineOrReference[T] {
  match
    opt_text(value, "$ref").map(v => {
      @reference.Reference::parse(v, limits=@exact.Limits::unlimited()).unwrap()
    }) {
    Some(ref_) => Reference(ref_)
    None => Inline(wrap(value))
  }
}

///|
fn[T] checked_object(
  value : @exact.Value,
  limits : @exact.Limits,
  decode : (@exact.Value, Array[String], @exact.Limits) -> T raise DecodeError,
) -> Result[T, @exact.Diagnostic] {
  match @exact.write(value, limits~) {
    Err(d) => return Err(d)
    Ok(_) => ()
  }
  Ok(decode(value, [], limits)) catch {
    DecodeError(d) => Err(d)
  }
}

///|
pub struct Contact {
  value : @exact.Value
} derive(Debug)

///|
pub fn Contact::to_json(self : Contact) -> @exact.Value {
  self.value
}

///|
pub fn Contact::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Contact, @exact.Diagnostic] {
  checked_object(value, limits, contact_)
}

///|
pub fn Contact::extensions(self : Contact) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Contact::additional_fields(
  self : Contact,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ContactObject)
}

///|
pub fn Contact::name(self : Contact) -> String? {
  opt_text(self.value, "name")
}

///|
pub fn Contact::url(self : Contact) -> @reference.UriReference? {
  opt_uri(self.value, "url")
}

///|
pub fn Contact::email(self : Contact) -> String? {
  opt_text(self.value, "email")
}

///|
pub extend Contact with @debug.Debug::{to_repr}

///|
pub struct License {
  value : @exact.Value
} derive(Debug)

///|
pub fn License::to_json(self : License) -> @exact.Value {
  self.value
}

///|
pub fn License::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[License, @exact.Diagnostic] {
  checked_object(value, limits, license_)
}

///|
pub fn License::extensions(self : License) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn License::additional_fields(
  self : License,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, LicenseObject)
}

///|
pub fn License::name(self : License) -> String? {
  opt_text(self.value, "name")
}

///|
pub fn License::url(self : License) -> @reference.UriReference? {
  opt_uri(self.value, "url")
}

///|
pub extend License with @debug.Debug::{to_repr}

///|
pub struct ExternalDocumentation {
  value : @exact.Value
} derive(Debug)

///|
pub fn ExternalDocumentation::to_json(
  self : ExternalDocumentation,
) -> @exact.Value {
  self.value
}

///|
pub fn ExternalDocumentation::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ExternalDocumentation, @exact.Diagnostic] {
  checked_object(value, limits, documentation_)
}

///|
pub fn ExternalDocumentation::extensions(
  self : ExternalDocumentation,
) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn ExternalDocumentation::additional_fields(
  self : ExternalDocumentation,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ExternalDocumentationObject)
}

///|
pub fn ExternalDocumentation::url(
  self : ExternalDocumentation,
) -> @reference.UriReference {
  opt_uri(self.value, "url").unwrap()
}

///|
pub fn ExternalDocumentation::description(
  self : ExternalDocumentation,
) -> String? {
  opt_text(self.value, "description")
}

///|
pub extend ExternalDocumentation with @debug.Debug::{to_repr}

///|
pub struct ServerVariable {
  value : @exact.Value
} derive(Debug)

///|
pub fn ServerVariable::to_json(self : ServerVariable) -> @exact.Value {
  self.value
}

///|
pub fn ServerVariable::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ServerVariable, @exact.Diagnostic] {
  checked_object(value, limits, variable_)
}

///|
pub fn ServerVariable::extensions(self : ServerVariable) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn ServerVariable::additional_fields(
  self : ServerVariable,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ServerVariableObject)
}

///|
pub fn ServerVariable::default_value(self : ServerVariable) -> String {
  req_text(self.value, "default")
}

///|
pub fn ServerVariable::description(self : ServerVariable) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn ServerVariable::enum_values(self : ServerVariable) -> Array[String]? {
  self.value.get("enum").map(v => value_array(v).map(v => v.text().unwrap()))
}

///|
pub extend ServerVariable with @debug.Debug::{to_repr}

///|
pub struct Server {
  value : @exact.Value
} derive(Debug)

///|
pub fn Server::to_json(self : Server) -> @exact.Value {
  self.value
}

///|
pub fn Server::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Server, @exact.Diagnostic] {
  checked_object(value, limits, server_)
}

///|
pub fn Server::extensions(self : Server) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Server::additional_fields(
  self : Server,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ServerObject)
}

///|
pub fn Server::url(self : Server) -> String {
  req_text(self.value, "url")
}

///|
pub fn Server::name(self : Server) -> String? {
  opt_text(self.value, "name")
}

///|
pub fn Server::summary(self : Server) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn Server::description(self : Server) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn Server::variables(self : Server) -> Array[(String, ServerVariable)]? {
  self.value
  .get("variables")
  .map(v => {
    value_fields(v).map(entry => (entry.0, ServerVariable::{ value: entry.1, }))
  })
}

///|
pub extend Server with @debug.Debug::{to_repr}

///|
pub struct Tag {
  value : @exact.Value
} derive(Debug)

///|
pub fn Tag::to_json(self : Tag) -> @exact.Value {
  self.value
}

///|
pub fn Tag::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Tag, @exact.Diagnostic] {
  checked_object(value, limits, tag_)
}

///|
pub fn Tag::extensions(self : Tag) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Tag::additional_fields(self : Tag) -> Array[(String, @exact.Value)] {
  extras_of(self.value, TagObject)
}

///|
pub fn Tag::name(self : Tag) -> String {
  req_text(self.value, "name")
}

///|
pub fn Tag::summary(self : Tag) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn Tag::description(self : Tag) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn Tag::external_docs(self : Tag) -> ExternalDocumentation? {
  self.value.get("externalDocs").map(v => ExternalDocumentation::{ value: v, })
}

///|
pub extend Tag with @debug.Debug::{to_repr}

///|
pub struct ErrorObject {
  value : @exact.Value
} derive(Debug)

///|
pub fn ErrorObject::to_json(self : ErrorObject) -> @exact.Value {
  self.value
}

///|
pub fn ErrorObject::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ErrorObject, @exact.Diagnostic] {
  checked_object(value, limits, error_object_)
}

///|
pub fn ErrorObject::extensions(self : ErrorObject) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn ErrorObject::additional_fields(
  self : ErrorObject,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ErrorObjectKind)
}

///|
pub fn ErrorObject::code(self : ErrorObject) -> ErrorCode {
  code_value(self.value.get("code").unwrap())
}

///|
pub fn ErrorObject::message(self : ErrorObject) -> String {
  req_text(self.value, "message")
}

///|
pub fn ErrorObject::data(self : ErrorObject) -> @exact.Value? {
  self.value.get("data")
}

///|
pub extend ErrorObject with @debug.Debug::{to_repr}

///|
pub struct Example {
  value : @exact.Value
} derive(Debug)

///|
pub fn Example::to_json(self : Example) -> @exact.Value {
  self.value
}

///|
pub fn Example::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Example, @exact.Diagnostic] {
  checked_object(value, limits, example_)
}

///|
pub fn Example::extensions(self : Example) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Example::additional_fields(
  self : Example,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ExampleObject)
}

///|
pub fn Example::name(self : Example) -> String? {
  opt_text(self.value, "name")
}

///|
pub fn Example::summary(self : Example) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn Example::description(self : Example) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn Example::payload(self : Example) -> ExampleValue {
  match self.value.get("value") {
    Some(v) => LiteralExample(v)
    None =>
      match opt_uri(self.value, "externalValue") {
        Some(uri) => ExternalExample(uri)
        None => NoExampleValue
      }
  }
}

///|
pub extend Example with @debug.Debug::{to_repr}

///|
pub struct ExamplePairing {
  value : @exact.Value
} derive(Debug)

///|
pub fn ExamplePairing::to_json(self : ExamplePairing) -> @exact.Value {
  self.value
}

///|
pub fn ExamplePairing::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[ExamplePairing, @exact.Diagnostic] {
  checked_object(value, limits, pairing_)
}

///|
pub fn ExamplePairing::extensions(self : ExamplePairing) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn ExamplePairing::additional_fields(
  self : ExamplePairing,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ExamplePairingObject)
}

///|
pub fn ExamplePairing::name(self : ExamplePairing) -> String {
  req_text(self.value, "name")
}

///|
pub fn ExamplePairing::summary(self : ExamplePairing) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn ExamplePairing::description(self : ExamplePairing) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn ExamplePairing::params(
  self : ExamplePairing,
) -> Array[InlineOrReference[Example]] {
  value_array(self.value.get("params").unwrap()).map(v => {
    reference_view(v, v => Example::{ value: v, })
  })
}

///|
pub fn ExamplePairing::result(
  self : ExamplePairing,
) -> InlineOrReference[Example]? {
  self.value
  .get("result")
  .map(v => reference_view(v, v => Example::{ value: v, }))
}

///|
pub extend ExamplePairing with @debug.Debug::{to_repr}

///|
pub struct Link {
  value : @exact.Value
} derive(Debug)

///|
pub fn Link::to_json(self : Link) -> @exact.Value {
  self.value
}

///|
pub fn Link::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Link, @exact.Diagnostic] {
  checked_object(value, limits, link_)
}

///|
pub fn Link::extensions(self : Link) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Link::additional_fields(self : Link) -> Array[(String, @exact.Value)] {
  extras_of(self.value, LinkObject)
}

///|
pub fn Link::name(self : Link) -> String? {
  opt_text(self.value, "name")
}

///|
pub fn Link::summary(self : Link) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn Link::description(self : Link) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn Link::target_method(self : Link) -> MethodName? {
  opt_text(self.value, "method").map(v => MethodName::parse(v).unwrap())
}

///|
pub fn Link::params(self : Link) -> Array[(String, @exact.Value)]? {
  self.value.get("params").map(value_fields)
}

///|
pub fn Link::server(self : Link) -> Server? {
  self.value.get("server").map(v => Server::{ value: v, })
}

///|
pub extend Link with @debug.Debug::{to_repr}

///|
pub fn Info::extensions(self : Info) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn Info::additional_fields(self : Info) -> Array[(String, @exact.Value)] {
  extras_of(self.value, InfoObject)
}

///|
pub fn Info::description(self : Info) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn Info::terms_of_service(self : Info) -> @reference.UriReference? {
  opt_uri(self.value, "termsOfService")
}

///|
pub fn Info::contact(self : Info) -> Contact? {
  self.value.get("contact").map(v => Contact::{ value: v, })
}

///|
pub fn Info::license(self : Info) -> License? {
  self.value.get("license").map(v => License::{ value: v, })
}

///|
pub fn ContentDescriptor::extensions(self : ContentDescriptor) -> Extensions {
  extensions_of(self.value)
}

///|
pub fn ContentDescriptor::additional_fields(
  self : ContentDescriptor,
) -> Array[(String, @exact.Value)] {
  extras_of(self.value, ContentDescriptorObject)
}

///|
pub fn ContentDescriptor::summary(self : ContentDescriptor) -> String? {
  opt_text(self.value, "summary")
}

///|
pub fn ContentDescriptor::description(self : ContentDescriptor) -> String? {
  opt_text(self.value, "description")
}

///|
pub fn ContentDescriptor::deprecated(self : ContentDescriptor) -> Bool? {
  opt_bool(self.value, "deprecated")
}

///|
pub fn Info::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Info, @exact.Diagnostic] {
  checked_object(value, limits, info_)
}
