///|
pub struct DocumentVersion {
  text : String
} derive(Eq, Debug)

///|
pub fn DocumentVersion::parse(
  text : String,
) -> Result[DocumentVersion, @exact.Diagnostic] {
  if text == "1.3.2" {
    return Ok({ text, })
  }
  if text.has_prefix("1.4.") {
    let patch = text[4:].to_owned()
    if !patch.is_empty() &&
      (patch == "0" || !patch.has_prefix("0")) &&
      patch.code_units().iter().all(c => c >= 48 && c <= 57) {
      return Ok({ text, })
    }
  }
  Err(
    @exact.Diagnostic::new(
      @exact.UnsupportedVersion,
      "Supported document versions are 1.3.2 and canonical 1.4.x",
      path=["openrpc"],
    ),
  )
}

///|
pub fn DocumentVersion::to_string(self : DocumentVersion) -> String {
  self.text
}

///|
pub struct MethodName {
  text : String
} derive(Eq, Debug)

///|
pub fn MethodName::parse(
  text : String,
) -> Result[MethodName, @exact.Diagnostic] {
  if text.is_empty() {
    Err(
      @exact.Diagnostic::new(@exact.WrongType, "A method name must be nonempty"),
    )
  } else {
    Ok({ text, })
  }
}

///|
pub fn MethodName::to_string(self : MethodName) -> String {
  self.text
}

///|
pub struct Info {
  title : String
  version : String
  value : @exact.Value
} derive(Debug)

///|
pub fn Info::title(self : Info) -> String {
  self.title
}

///|
pub fn Info::version(self : Info) -> String {
  self.version
}

///|
pub fn Info::to_json(self : Info) -> @exact.Value {
  self.value
}

///|
pub struct ContentDescriptor {
  name : String
  schema : @schema.Schema
  required : Bool?
  value : @exact.Value
} derive(Debug)

///|
pub fn ContentDescriptor::name(self : ContentDescriptor) -> String {
  self.name
}

///|
pub fn ContentDescriptor::schema(self : ContentDescriptor) -> @schema.Schema {
  self.schema
}

///|
pub fn ContentDescriptor::required(self : ContentDescriptor) -> Bool? {
  self.required
}

///|
pub fn ContentDescriptor::to_json(self : ContentDescriptor) -> @exact.Value {
  self.value
}

///|
pub(all) enum InlineOrReference[T] {
  Inline(T)
  Reference(@reference.Reference)
} derive(Debug)

///|
pub(all) enum ParamStructure {
  ByName
  ByPosition
  Either
} derive(Eq, Debug)

///|
pub struct Method {
  name : MethodName
  params : Array[InlineOrReference[ContentDescriptor]]
  result : InlineOrReference[ContentDescriptor]?
  param_structure : ParamStructure?
  value : @exact.Value
} derive(Debug)

///|
pub fn Method::name(self : Method) -> MethodName {
  self.name
}

///|
pub fn Method::params(
  self : Method,
) -> Array[InlineOrReference[ContentDescriptor]] {
  self.params.copy()
}

///|
pub fn Method::result(self : Method) -> InlineOrReference[ContentDescriptor]? {
  self.result
}

///|
pub fn Method::param_structure(self : Method) -> ParamStructure? {
  self.param_structure
}

///|
pub fn Method::to_json(self : Method) -> @exact.Value {
  self.value
}

///|
pub struct Document {
  version : DocumentVersion
  info : Info
  methods : Array[InlineOrReference[Method]]
  value : @exact.Value
  schema_uri : @reference.UriReference?
  servers : Array[Server]?
  components : Components?
  external_docs : ExternalDocumentation?
} derive(Debug)

///|
pub fn Document::version(self : Document) -> DocumentVersion {
  self.version
}

///|
pub fn Document::info(self : Document) -> Info {
  self.info
}

///|
pub fn Document::methods(self : Document) -> Array[InlineOrReference[Method]] {
  self.methods.copy()
}

///|
pub fn Document::to_json(self : Document) -> @exact.Value {
  self.value
}

///|
pub struct ReadResult {
  cst : @exact.CstDocument?
  document : Document?
  diagnostics : Array[@exact.Diagnostic]
} derive(Debug)

///|
pub fn ReadResult::cst(self : ReadResult) -> @exact.CstDocument? {
  self.cst
}

///|
pub fn ReadResult::source_map(self : ReadResult) -> @exact.SourceMap? {
  self.cst.map(cst => cst.source_map())
}

///|
pub fn ReadResult::document(self : ReadResult) -> Document? {
  self.document
}

///|
pub fn ReadResult::diagnostics(self : ReadResult) -> Array[@exact.Diagnostic] {
  self.diagnostics.copy()
}

///|
pub extend DocumentVersion with Eq::{equal, not_equal}

///|
pub extend DocumentVersion with @debug.Debug::{to_repr}

///|
pub extend MethodName with Eq::{equal, not_equal}

///|
pub extend MethodName with @debug.Debug::{to_repr}

///|
pub extend Info with @debug.Debug::{to_repr}

///|
pub extend ContentDescriptor with @debug.Debug::{to_repr}

///|
pub extend InlineOrReference with @debug.Debug::{to_repr}

///|
pub extend ParamStructure with Eq::{equal, not_equal}

///|
pub extend ParamStructure with @debug.Debug::{to_repr}

///|
pub extend Method with @debug.Debug::{to_repr}

///|
pub extend Document with @debug.Debug::{to_repr}

///|
pub extend ReadResult with @debug.Debug::{to_repr}
