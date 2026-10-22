///|
/// A schema retains exact JSON with checked typed keyword forms.
pub struct Schema {
  value : @json.Value
} derive(Debug)

///|
pub extend Schema with @debug.Debug::{to_repr}

///|
pub fn Schema::from_json(
  value : @json.Value,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Schema, @json.Diagnostic] {
  decode_schema(value, limits)
}

///|
/// Report malformed schema documents without constructing an invalid typed AST.
pub fn validate_json(
  value : @json.Value,
  root~ : @json.Value,
  path~ : Array[String] = [],
  base~ : @reference.UriReference? = None,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
  max_nodes~ : Int32 = 10000,
  max_edges~ : Int32 = 4096,
  max_findings~ : Int32 = 256,
  max_comparison_work~ : Int32 = 1000000,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Report {
  validate(
    Schema::{ value, },
    root~,
    path~,
    base~,
    resources~,
    max_nodes~,
    max_edges~,
    max_findings~,
    max_comparison_work~,
    limits~,
  )
}

///|
pub fn Schema::to_json(self : Schema) -> @json.Value {
  self.value
}

///|
/// Completeness means all requested schema-document checks were performed.
/// It does not mean that the diagnostics contain no failures.
pub struct Report {
  priv findings : Array[@json.Diagnostic]
  complete : Bool
  references_complete : Bool
  priv resolutions : Array[@reference.Resolution]
  priv owners : Array[@reference.UriReference?]
} derive(Debug)

///|
pub extend Report with @debug.Debug::{to_repr}

///|
pub fn Report::diagnostics(self : Report) -> Array[@json.Diagnostic] {
  self.findings.copy()
}

///|
pub fn Report::is_complete(self : Report) -> Bool {
  self.complete
}

///|
/// Whether every followed reference and every schema identifier was resolved
/// or definitively failed. Local keyword and regex checks are reported
/// separately through `is_complete`.
pub fn Report::references_complete(self : Report) -> Bool {
  self.references_complete
}

///|
/// One resolution per followed `$ref` edge, in traversal order.
pub fn Report::diagnostic_resources(
  self : Report,
) -> Array[@reference.UriReference?] {
  self.owners.copy()
}

///|
pub fn Report::resolutions(self : Report) -> Array[@reference.Resolution] {
  self.resolutions.copy()
}

///|
fn schema_kind(value : @json.Value) -> Bool {
  match value.kind() {
    @json.Object(_) | @json.Boolean(_) => true
    _ => false
  }
}

///|
/// Validate a bounded schema-document graph without evaluating instances.
/// References resolve through nested `$id` scopes and the explicit
/// `resources`; nothing is fetched.
pub fn validate(
  schema : Schema,
  root~ : @json.Value,
  path~ : Array[String] = [],
  base~ : @reference.UriReference? = None,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
  max_nodes~ : Int32 = 10000,
  max_edges~ : Int32 = 4096,
  max_findings~ : Int32 = 256,
  max_comparison_work~ : Int32 = 1000000,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Report {
  check_schema(
    schema.value,
    root,
    path,
    base,
    resources,
    max_nodes,
    max_edges,
    max_findings,
    max_comparison_work,
    limits,
  )
}
