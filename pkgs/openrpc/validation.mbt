///|
pub(all) enum Coverage {
  Passed
  Failed
  Incomplete
} derive(Eq, Debug)

///|
pub(all) enum ValidationProfile {
  Specification
  MetaschemaCompatibility
} derive(Eq, Debug)

///|
pub(all) enum Severity {
  Error
  Warning
  Information
} derive(Eq, Debug)

///|
pub(all) enum Phase {
  Model
  SchemaDocument
  References
  Normative
  Artifact
} derive(Eq, Debug)

///|
pub struct Finding {
  diagnostic : @exact.Diagnostic
  severity : Severity
  phase : Phase
} derive(Debug)

///|
pub fn Finding::diagnostic(self : Finding) -> @exact.Diagnostic {
  self.diagnostic
}

///|
pub fn Finding::severity(self : Finding) -> Severity {
  self.severity
}

///|
pub fn Finding::phase(self : Finding) -> Phase {
  self.phase
}

///|
pub struct ValidationReport {
  profile : ValidationProfile
  findings : Array[Finding]
  model : Coverage
  schemas : Coverage
  references : Coverage
  normative : Coverage
  artifact : Coverage
} derive(Debug)

///|
pub fn ValidationReport::profile(self : ValidationReport) -> ValidationProfile {
  self.profile
}

///|
pub fn ValidationReport::findings(self : ValidationReport) -> Array[Finding] {
  self.findings.copy()
}

///|
pub fn ValidationReport::model(self : ValidationReport) -> Coverage {
  self.model
}

///|
pub fn ValidationReport::schemas(self : ValidationReport) -> Coverage {
  self.schemas
}

///|
pub fn ValidationReport::references(self : ValidationReport) -> Coverage {
  self.references
}

///|
pub fn ValidationReport::normative(self : ValidationReport) -> Coverage {
  self.normative
}

///|
pub fn ValidationReport::artifact(self : ValidationReport) -> Coverage {
  self.artifact
}

///|
pub struct ValidatedDocument {
  document : Document
  report : ValidationReport
} derive(Debug)

///|
pub fn ValidatedDocument::document(self : ValidatedDocument) -> Document {
  self.document
}

///|
pub fn ValidatedDocument::report(self : ValidatedDocument) -> ValidationReport {
  self.report
}

///|
pub struct ClosedValidation {
  report : ValidationReport
  document : ValidatedDocument?
} derive(Debug)

///|
pub fn ClosedValidation::report(self : ClosedValidation) -> ValidationReport {
  self.report
}

///|
pub fn ClosedValidation::document(
  self : ClosedValidation,
) -> ValidatedDocument? {
  self.document
}

///|
fn add(
  findings : Array[Finding],
  code : @exact.Code,
  message : String,
  path : Array[String],
  phase : Phase,
  severity~ : Severity = Error,
) -> Unit {
  findings.push({
    diagnostic: @exact.Diagnostic::new(code, message, path~),
    phase,
    severity,
  })
}

///|
fn unsupported_fields(
  value : @exact.Value,
  allowed : Array[String],
  path : Array[String],
  findings : Array[Finding],
) -> Unit {
  guard value.kind() is @exact.Object(fields) else { return }
  for (key, _) in fields {
    if !allowed.contains(key) && !key.has_prefix("x-") {
      add(
        findings,
        @exact.UnsupportedCheck,
        "Field retained; complete model checks require a later implementation story",
        child(path, key),
        Model,
        severity=Information,
      )
    }
  }
}

///|
/// Codes for references whose inputs were not supplied: incomplete, not failed.
fn unavailable(code : @exact.Code) -> Bool {
  code == @exact.MissingBaseUri || code == @exact.UnavailableResource
}

///|
fn reference_severity(code : @exact.Code) -> Severity {
  if unavailable(code) || code == @exact.UnsupportedCheck {
    Information
  } else {
    Error
  }
}

///|
/// One validation pass over a document and its explicit resources. Every
/// reference site resolves through one schema index; targets in other
/// resources are reported at their own resource-relative pointer.
priv struct Check {
  index : @reference.SchemaIndex
  findings : Array[Finding]
  checked : Set[String]
  limits : @exact.Limits
}

///|
fn site_key(owner : @reference.UriReference?, path : Array[String]) -> String {
  let resource = match owner {
    Some(uri) => uri.identity()
    None => ""
  }
  let pointer = @reference.JsonPointer::from_tokens(
    path,
    limits=@exact.Limits::unlimited(),
  ).unwrap()
  resource + "#" + pointer.to_string()
}

///|
/// Follow a reference-only chain to a concrete object. Each reference resolves
/// against the resource that holds it. Revisiting a location is a cycle.
fn Check::follow(
  self : Check,
  value : @exact.Value,
  owner : @reference.UriReference?,
  path : Array[String],
) -> (@exact.Value, @reference.UriReference?, Array[String])? {
  let mut current = value
  let mut owner = owner
  let mut at = path
  let seen : Set[String] = Set([])
  for _ in 0..<self.limits.max_depth() {
    guard current.get("$ref") is Some(raw) else {
      return Some((current, owner, at))
    }
    let site = child(at, "$ref")
    guard raw.text() is Some(text) else {
      add(
        self.findings,
        @exact.InvalidReference,
        "Reference must be a string",
        site,
        References,
      )
      return None
    }
    let ref_ = match @reference.Reference::parse(text, limits=self.limits) {
      Ok(v) => v
      Err(d) => {
        add(self.findings, d.code(), d.message(), site, References)
        return None
      }
    }
    let resolution = self.index.resolve(ref_, base=owner, limits=self.limits)
    guard resolution.target() is Some(target) else {
      for d in resolution.diagnostics() {
        add(
          self.findings,
          d.code(),
          d.message(),
          site,
          References,
          severity=reference_severity(d.code()),
        )
      }
      return None
    }
    if !seen.add_and_check(target.identity()) {
      add(
        self.findings,
        @exact.ReferenceCycle,
        "OpenRPC reference-only cycle has no concrete target",
        site,
        References,
      )
      return None
    }
    current = target.target()
    owner = target.resource()
    at = target.pointer().tokens()
  }
  add(
    self.findings,
    @exact.LimitExceeded,
    "OpenRPC reference chain limit exceeded",
    path,
    References,
  )
  None
}

///|
/// Resolve a site and decode its target with the expected kind's checked
/// decoder. A referenced target of another kind is `WrongType` at the site.
fn[T] Check::typed(
  self : Check,
  value : @exact.Value,
  owner : @reference.UriReference?,
  path : Array[String],
  kind : String,
  decode : (@exact.Value, Array[String]) -> T raise DecodeError,
) -> (T, @reference.UriReference?, Array[String])? {
  let referenced = value.get("$ref") is Some(_)
  guard self.follow(value, owner, path) is Some((target, owner, at)) else {
    return None
  }
  let decoded = decode(target, at) catch {
    DecodeError(d) => {
      if referenced {
        add(
          self.findings,
          @exact.WrongType,
          "Reference target is not a valid " + kind + ": " + d.message(),
          child(path, "$ref"),
          References,
        )
      } else {
        self.findings.push({ diagnostic: d, severity: Error, phase: Model, })
      }
      return None
    }
  }
  Some((decoded, owner, at))
}

///|
fn Check::schema(
  self : Check,
  schema : @schema.Schema,
  owner : @reference.UriReference?,
  path : Array[String],
) -> Unit {
  // Findings depend only on the schema location, so each is checked once no
  // matter how many reference sites reach it.
  if !self.checked.add_and_check("schema " + site_key(owner, path)) {
    return
  }
  let report = @schema.validate_in(
    schema,
    index=self.index,
    resource=owner,
    path~,
    limits=self.limits,
  )
  for d in report.diagnostics() {
    let ref_finding = d.code() == @exact.UnresolvedReference ||
      d.code() == @exact.InvalidReference ||
      d.code() == @exact.ConflictingIdentifier ||
      unavailable(d.code()) ||
      (d.code() == @exact.UnsupportedCheck && d.path().last() == Some("$ref"))
    self.findings.push({
      diagnostic: @exact.Diagnostic::new(d.code(), d.message(), path=d.path()),
      phase: if ref_finding {
        References
      } else {
        SchemaDocument
      },
      severity: if d.code() == @exact.UnsupportedCheck ||
        d.code() == @exact.UnsupportedDialect ||
        unavailable(d.code()) {
        Information
      } else {
        Error
      },
    })
  }
  if !report.is_complete() && report.diagnostics().is_empty() {
    add(
      self.findings,
      @exact.UnsupportedCheck,
      "Schema checks incomplete",
      path,
      SchemaDocument,
      severity=Information,
    )
  }
}

///|
fn descriptor_decoder(
  limits : @exact.Limits,
) -> (@exact.Value, Array[String]) -> ContentDescriptor raise DecodeError {
  (v, p) => {
    guard descriptor(v, p, limits~) is Inline(d) else {
      raise DecodeError(
        @exact.Diagnostic::new(@exact.WrongType, "Expected an object", path=p),
      )
    }
    d
  }
}

///|
fn Check::pairing(
  self : Check,
  value : @exact.Value,
  owner : @reference.UriReference?,
  path : Array[String],
) -> Unit {
  let limits = self.limits
  guard self.typed(value, owner, path, "example pairing", (v, p) => {
      pairing_(v, p, limits)
    })
    is Some((pairing, owner, at)) else {
    return
  }
  if !self.checked.add_and_check("pairing " + site_key(owner, at)) {
    return
  }
  let example = (v, p) => example_(v, p, limits)
  if pairing.value.get("params") is Some(params) &&
    params.kind() is @exact.Array(items) {
    for i, item in items {
      self.typed(
        item,
        owner,
        child(child(at, "params"), i.to_string()),
        "example",
        example,
      )
      |> ignore
    }
  }
  if pairing.value.get("result") is Some(result) {
    self.typed(result, owner, child(at, "result"), "example", example) |> ignore
  }
}

///|
fn Check::items(
  self : Check,
  method_ : Method,
  owner : @reference.UriReference?,
  path : Array[String],
  name : String,
  kind : String,
  decode : (@exact.Value, Array[String]) -> Unit raise DecodeError,
) -> Unit {
  guard method_.value.get(name) is Some(raw) &&
    raw.kind() is @exact.Array(items) else {
    return
  }
  for i, item in items {
    self.typed(
      item,
      owner,
      child(child(path, name), i.to_string()),
      kind,
      decode,
    )
    |> ignore
  }
}

///|
/// Draft-07 schema positions the typed model knows in a document.
fn document_schema_roots(document : Document) -> Array[Array[String]] {
  let roots = []
  for i, method_ in document.methods {
    guard method_ is Inline(m) else { continue }
    let at = ["methods", i.to_string()]
    for j, param in m.params {
      if param is Inline(_) {
        roots.push([..at, "params", j.to_string(), "schema"])
      }
    }
    if m.result is Some(Inline(_)) {
      roots.push([..at, "result", "schema"])
    }
  }
  if document.components is Some(components) {
    if components.schemas() is Some(schemas) {
      for entry in schemas {
        roots.push(["components", "schemas", entry.0.to_string()])
      }
    }
    if components.content_descriptors() is Some(descriptors) {
      for entry in descriptors {
        roots.push([
          "components",
          "contentDescriptors",
          entry.0.to_string(),
          "schema",
        ])
      }
    }
  }
  roots
}

///|
/// The document as an explicit resource whose schema roots are every schema
/// position in its typed model. Other values stay opaque.
pub fn Document::as_resource(
  self : Document,
  uri : @reference.UriReference,
  aliases~ : Array[@reference.UriReference] = [],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[@reference.Resource, @exact.Diagnostic] {
  let roots = []
  for tokens in document_schema_roots(self) {
    match @reference.JsonPointer::from_tokens(tokens, limits~) {
      Ok(pointer) => roots.push(pointer)
      Err(d) => return Err(d)
    }
  }
  @reference.Resource::new(
    uri,
    self.value,
    aliases~,
    schema_roots=roots,
    limits~,
  )
}

///|
/// Build the index for a document. A registered base holding exactly this
/// document makes it the physical resource; otherwise the document is the
/// unnamed input under the optional base.
fn document_index(
  document : Document,
  resources : @reference.ResourceSet,
  base : @reference.UriReference?,
  limits : @exact.Limits,
) -> (@reference.SchemaIndex, @reference.UriReference?) {
  let roots = document_schema_roots(document).map(tokens => {
    @reference.JsonPointer::from_tokens(
      tokens,
      limits=@exact.Limits::unlimited(),
    ).unwrap()
  })
  let registered = match base {
    Some(base) => resources.get(base)
    None => None
  }
  if registered is Some(resource) &&
    resource.value().equals(document.value, limits~) is Ok(true) {
    let declared = resource.schema_roots()
    let known : Set[String] = Set(declared.map(p => p.to_string()))
    for root in roots {
      if known.add_and_check(root.to_string()) {
        declared.push(root)
      }
    }
    let trusted = @exact.Limits::unlimited()
    let identity = resource.uri().identity()
    let replaced = @reference.Resource::new(
      resource.uri(),
      resource.value(),
      aliases=resource.aliases(),
      schema_roots=declared,
      limits=trusted,
    )
    let set = match replaced {
      Ok(replaced) =>
        @reference.ResourceSet::new(
          resources
          .resources()
          .map(r => if r.uri().identity() == identity { replaced } else { r }),
          root_base=resources.root_base(),
          limits=trusted,
        )
      Err(d) => Err(d)
    }
    // Re-registration only adds checked roots; keep the caller's set if not.
    let set = match set {
      Ok(set) => set
      Err(_) => resources
    }
    return (@reference.SchemaIndex::new(set, limits~), Some(resource.uri()))
  }
  (
    @reference.SchemaIndex::new(
      resources,
      input=Some(document.value),
      input_base=base,
      input_roots=roots,
      limits~,
    ),
    base,
  )
}

///|
fn coverage(findings : Array[Finding], phase : Phase) -> Coverage {
  if findings.any(f => {
      f.phase == phase &&
      f.severity == Error &&
      f.diagnostic.code() != @exact.LimitExceeded
    }) {
    Failed
  } else if findings.any(f => {
      f.phase == phase &&
      (
        f.diagnostic.code() == @exact.UnsupportedCheck ||
        f.diagnostic.code() == @exact.UnsupportedDialect ||
        f.diagnostic.code() == @exact.LimitExceeded ||
        unavailable(f.diagnostic.code())
      )
    }) {
    Incomplete
  } else {
    Passed
  }
}

///|
/// Validate a document against explicit resources. `base` is the document's
/// retrieval URI; relative references and schema identifiers need it. Nothing
/// is fetched. Unsupplied resources leave reference coverage incomplete.
pub fn validate(
  document : Document,
  profile~ : ValidationProfile = Specification,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
  base~ : @reference.UriReference? = None,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> ValidationReport {
  let findings : Array[Finding] = []
  let base = match base {
    Some(uri) if !uri.is_absolute() || uri.fragment() is Some(_) => {
      add(
        findings,
        @exact.InvalidReference,
        "Document base URI must be absolute and fragment-free",
        [],
        References,
      )
      None
    }
    _ => base
  }
  let (index, owner) = document_index(document, resources, base, limits)
  for d in index.diagnostics() {
    add(
      findings,
      d.code(),
      d.message(),
      d.path(),
      References,
      severity=reference_severity(d.code()),
    )
  }
  let check = Check::{ index, findings, checked: Set([]), limits, }
  let root = document.value
  unsupported_fields(
    root,
    ["openrpc", "info", "methods", "components", "$schema"],
    [],
    findings,
  )
  unsupported_fields(
    document.info.value,
    ["title", "version"],
    ["info"],
    findings,
  )
  if root.get("$schema") is Some(value) && value.text() is None {
    add(
      findings,
      @exact.WrongType,
      "Root $schema must be a string",
      ["$schema"],
      Model,
    )
  }
  let names : Set[String] = Set([])
  let raw_methods = match root.get("methods") {
    Some(raw) =>
      match raw.kind() {
        @exact.Array(items) => items
        _ => []
      }
    None => []
  }
  for i, raw_method in raw_methods {
    let path = ["methods", i.to_string()]
    guard check.typed(raw_method, owner, path, "method", (v, p) => {
        match method_(v, p, limits~) {
          Inline(m) => m
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
      is Some((method_, method_owner, method_path)) else {
      continue
    }
    unsupported_fields(
      method_.value,
      ["name", "params", "result", "paramStructure"],
      method_path,
      findings,
    )
    if names.contains(method_.name.text) {
      add(
        findings,
        @exact.DuplicateKey,
        "Method names must be unique",
        child(path, "name"),
        Normative,
      )
    }
    names.add(method_.name.text)
    let param_names : Set[String] = Set([])
    let mut optional_seen = false
    let raw_params = match method_.value.get("params") {
      Some(raw) =>
        match raw.kind() {
          @exact.Array(items) => items
          _ => []
        }
      None => []
    }
    for pi, raw_param in raw_params {
      let param_path = child(child(method_path, "params"), pi.to_string())
      guard check.typed(
          raw_param,
          method_owner,
          param_path,
          "content descriptor",
          descriptor_decoder(limits),
        )
        is Some((desc, desc_owner, desc_path)) else {
        continue
      }
      unsupported_fields(
        desc.value,
        ["name", "schema", "required"],
        desc_path,
        findings,
      )
      if param_names.contains(desc.name) {
        add(
          findings,
          @exact.DuplicateKey,
          "Parameter names must be unique",
          child(param_path, "name"),
          Normative,
        )
      }
      param_names.add(desc.name)
      let required = desc.required.unwrap_or(false)
      if required && optional_seen {
        add(
          findings,
          @exact.ParameterOrder,
          "Optional parameters precede a required parameter",
          param_path,
          Normative,
          severity=if profile == Specification { Error } else { Warning },
        )
      }
      if !required {
        optional_seen = true
      }
      check.schema(desc.schema, desc_owner, child(desc_path, "schema"))
    }
    if method_.value.get("result") is Some(raw_result) {
      let result_path = child(method_path, "result")
      if check.typed(
          raw_result,
          method_owner,
          result_path,
          "content descriptor",
          descriptor_decoder(limits),
        )
        is Some((desc, desc_owner, desc_path)) {
        unsupported_fields(
          desc.value,
          ["name", "schema", "required"],
          desc_path,
          findings,
        )
        check.schema(desc.schema, desc_owner, child(desc_path, "schema"))
      }
    }
    check.items(method_, method_owner, method_path, "errors", "error", (v, p) => {
      error_object_(v, p, limits) |> ignore
    })
    check.items(method_, method_owner, method_path, "links", "link", (v, p) => {
      link_(v, p, limits) |> ignore
    })
    check.items(method_, method_owner, method_path, "tags", "tag", (v, p) => {
      tag_(v, p, limits) |> ignore
    })
    if method_.value.get("examples") is Some(raw) &&
      raw.kind() is @exact.Array(items) {
      for ei, item in items {
        check.pairing(
          item,
          method_owner,
          child(child(method_path, "examples"), ei.to_string()),
        )
      }
    }
  }
  if root.get("components") is Some(components) {
    match components.kind() {
      @exact.Object(_) => {
        unsupported_fields(components, ["schemas"], ["components"], findings)
        if components.get("schemas") is Some(schemas) {
          match schemas.kind() {
            @exact.Object(entries) =>
              for (name, value) in entries {
                let path = ["components", "schemas", name]
                if ComponentKey::parse(name) is Err(_) {
                  add(
                    findings,
                    @exact.WrongType,
                    "Component keys must match ^[a-zA-Z0-9.\\-_]+$",
                    path,
                    Normative,
                  )
                }
                match @schema.Schema::from_json(value, limits~) {
                  Ok(schema) => check.schema(schema, owner, path)
                  Err(d) => {
                    let at = path.copy()
                    for part in d.path() {
                      at.push(part)
                    }
                    add(findings, d.code(), d.message(), at, SchemaDocument)
                  }
                }
              }
            _ =>
              add(
                findings,
                @exact.WrongType,
                "Schema components must be an object",
                ["components", "schemas"],
                Model,
              )
          }
        }
        if document.components is Some(typed) &&
          typed.content_descriptors() is Some(descriptors) {
          for entry in descriptors {
            check.schema(entry.1.schema(), owner, [
              "components",
              "contentDescriptors",
              entry.0.to_string(),
              "schema",
            ])
          }
        }
        if components.get("examplePairings") is Some(pairings) &&
          pairings.kind() is @exact.Object(entries) {
          for (name, value) in entries {
            check.pairing(value, owner, ["components", "examplePairings", name])
          }
        }
      }
      _ =>
        add(
          findings,
          @exact.WrongType,
          "Components must be an object",
          ["components"],
          Model,
        )
    }
  }
  add(
    findings,
    @exact.UnsupportedCheck,
    "Pinned metaschema compatibility is not complete in the tracer",
    [],
    Artifact,
    severity=Information,
  )
  // A component reached from several sites is checked once per site; report
  // each distinct finding once.
  let unique : Array[Finding] = []
  let seen : Set[String] = Set([])
  for f in findings {
    let key = f.phase.to_repr().to_string() +
      "|" +
      f.severity.to_repr().to_string() +
      "|" +
      f.diagnostic.code().to_repr().to_string() +
      "|" +
      site_key(None, f.diagnostic.path()) +
      "|" +
      f.diagnostic.message()
    if seen.add_and_check(key) {
      unique.push(f)
    }
  }
  {
    profile,
    model: coverage(unique, Model),
    schemas: coverage(unique, SchemaDocument),
    references: coverage(unique, References),
    normative: coverage(unique, Normative),
    artifact: coverage(unique, Artifact),
    findings: unique,
  }
}

///|
pub fn validate_closed(
  document : Document,
  profile~ : ValidationProfile = Specification,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
  base~ : @reference.UriReference? = None,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> ClosedValidation {
  let report = validate(document, profile~, resources~, base~, limits~)
  let passed = report.model == Passed &&
    report.schemas == Passed &&
    report.references == Passed &&
    report.normative == Passed &&
    (profile == Specification || report.artifact == Passed)
  { report, document: if passed { Some({ document, report, }) } else { None }, }
}

///|
pub extend Coverage with Eq::{equal, not_equal}

///|
pub extend Coverage with @debug.Debug::{to_repr}

///|
pub extend ValidationProfile with Eq::{equal, not_equal}

///|
pub extend ValidationProfile with @debug.Debug::{to_repr}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub extend Phase with Eq::{equal, not_equal}

///|
pub extend Phase with @debug.Debug::{to_repr}

///|
pub extend Finding with @debug.Debug::{to_repr}

///|
pub extend ValidationReport with @debug.Debug::{to_repr}

///|
pub extend ValidatedDocument with @debug.Debug::{to_repr}

///|
pub extend ClosedValidation with @debug.Debug::{to_repr}
