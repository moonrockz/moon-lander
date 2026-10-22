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
/// Where a finding applies. `resource` is None for the unnamed input document.
/// Spans exist only for the input document, and only when its source map was
/// supplied.
pub struct FindingLocation {
  priv resource : @reference.UriReference?
  priv path : Array[String]
  priv span : @exact.Span?
  priv source_id : String?
} derive(Debug)

///|
pub fn FindingLocation::resource(
  self : FindingLocation,
) -> @reference.UriReference? {
  self.resource
}

///|
pub fn FindingLocation::path(self : FindingLocation) -> Array[String] {
  self.path.copy()
}

///|
pub fn FindingLocation::span(self : FindingLocation) -> @exact.Span? {
  self.span
}

///|
pub fn FindingLocation::source_id(self : FindingLocation) -> String? {
  self.source_id
}

///|
pub struct Finding {
  diagnostic : @exact.Diagnostic
  severity : Severity
  phase : Phase
  priv location : FindingLocation
  priv related : Array[FindingLocation]
  priv chain : Array[FindingLocation]
  priv expected : String?
  priv discrepancy : Discrepancy?
  priv version : DocumentVersion
  priv profile : ValidationProfile
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
pub fn Finding::location(self : Finding) -> FindingLocation {
  self.location
}

///|
/// Other occurrences involved, such as the first of two duplicates.
pub fn Finding::related(self : Finding) -> Array[FindingLocation] {
  self.related.copy()
}

///|
/// OpenRPC `$ref` sites followed, in order, to reach the location.
pub fn Finding::chain(self : Finding) -> Array[FindingLocation] {
  self.chain.copy()
}

///|
/// The missing member's name when the location is its parent object.
pub fn Finding::expected_field(self : Finding) -> String? {
  self.expected
}

///|
/// The recorded prose/artifact discrepancy this normative finding belongs to.
pub fn Finding::discrepancy(self : Finding) -> Discrepancy? {
  self.discrepancy
}

///|
pub fn Finding::version(self : Finding) -> DocumentVersion {
  self.version
}

///|
pub fn Finding::profile(self : Finding) -> ValidationProfile {
  self.profile
}

///|
pub struct ValidationReport {
  profile : ValidationProfile
  version : DocumentVersion
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
pub fn ValidationReport::version(self : ValidationReport) -> DocumentVersion {
  self.version
}

///|
/// Findings in deterministic order: resource, pointer tokens, code, source
/// occurrence, then message.
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
/// A document whose required facets all passed for one profile and one
/// explicit resource snapshot.
pub struct ValidatedDocument {
  document : Document
  report : ValidationReport
  priv resources : Array[@reference.UriReference]
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
pub fn ValidatedDocument::profile(
  self : ValidatedDocument,
) -> ValidationProfile {
  self.report.profile
}

///|
pub fn ValidatedDocument::version(self : ValidatedDocument) -> DocumentVersion {
  self.document.version
}

///|
/// Retrieval URIs of the resource snapshot the document was closed against.
pub fn ValidatedDocument::resources(
  self : ValidatedDocument,
) -> Array[@reference.UriReference] {
  self.resources.copy()
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
/// A pointer in one resource; None is the unnamed input document.
priv struct Site {
  resource : @reference.UriReference?
  path : Array[String]
}

///|
/// A finding before source lookup, ordering and limits.
priv struct Draft {
  diagnostic : @exact.Diagnostic
  severity : Severity
  phase : Phase
  site : Site
  related : Array[Site]
  chain : Array[Site]
  expected : String?
  discrepancy : Discrepancy?
}

///|
fn add(
  findings : Array[Draft],
  code : @exact.Code,
  message : String,
  path : Array[String],
  phase : Phase,
  severity~ : Severity = Error,
  resource~ : @reference.UriReference? = None,
  related~ : Array[Site] = [],
  chain~ : Array[Site] = [],
  expected~ : String? = None,
  discrepancy~ : Discrepancy? = None,
) -> Unit {
  findings.push({
    diagnostic: @exact.Diagnostic::new(code, message, path~),
    phase,
    severity,
    site: { resource, path },
    related,
    chain,
    expected,
    discrepancy,
  })
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
  findings : Array[Draft]
  checked : Set[String]
  limits : @exact.Limits
  version : DocumentVersion
  profile : ValidationProfile
  links : Array[(String, Site, Array[Site])]
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
/// A resolved OpenRPC object: its value, owning resource, pointer there, and
/// the `$ref` sites followed to reach it.
priv struct Resolved[T] {
  value : T
  owner : @reference.UriReference?
  path : Array[String]
  chain : Array[Site]
}

///|
/// Follow a reference-only chain to a concrete object. Each reference resolves
/// against the resource that holds it. Revisiting a location is a cycle.
fn Check::follow(
  self : Check,
  value : @exact.Value,
  owner : @reference.UriReference?,
  path : Array[String],
  chain : Array[Site],
) -> Resolved[@exact.Value]? {
  let mut current = value
  let mut owner = owner
  let mut at = path
  let chain = chain.copy()
  let seen : Set[String] = Set([])
  for _ in 0..<self.limits.max_depth() {
    guard current.get("$ref") is Some(raw) else {
      return Some({ value: current, owner, path: at, chain })
    }
    let site = child(at, "$ref")
    let fail = (code, message, severity) => {
      add(
        self.findings,
        code,
        message,
        site,
        References,
        severity~,
        resource=owner,
        chain=chain.copy(),
      )
    }
    guard raw.text() is Some(text) else {
      fail(@exact.InvalidReference, "Reference must be a string", Error)
      return None
    }
    let ref_ = match @reference.Reference::parse(text, limits=self.limits) {
      Ok(v) => v
      Err(d) => {
        fail(d.code(), d.message(), Error)
        return None
      }
    }
    let resolution = self.index.resolve(ref_, base=owner, limits=self.limits)
    guard resolution.target() is Some(target) else {
      for d in resolution.diagnostics() {
        fail(d.code(), d.message(), reference_severity(d.code()))
      }
      return None
    }
    if !seen.add_and_check(target.identity()) {
      fail(
        @exact.ReferenceCycle,
        "OpenRPC reference-only cycle has no concrete target",
        Error,
      )
      return None
    }
    chain.push({ resource: owner, path: site })
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
    resource=owner,
    chain~,
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
  chain~ : Array[Site] = [],
) -> Resolved[T]? {
  let referenced = value.get("$ref") is Some(_)
  guard self.follow(value, owner, path, chain) is Some(target) else {
    return None
  }
  let decoded = decode(target.value, target.path) catch {
    DecodeError(d) => {
      if referenced {
        let last = target.chain[target.chain.length() - 1]
        add(
          self.findings,
          @exact.WrongType,
          "Reference target is not a valid " + kind + ": " + d.message(),
          last.path,
          References,
          resource=last.resource,
          chain=target.chain[:target.chain.length() - 1].to_owned(),
        )
      } else {
        add(
          self.findings,
          d.code(),
          d.message(),
          d.path(),
          Model,
          resource=target.owner,
          chain=target.chain,
        )
      }
      return None
    }
  }
  Some({
    value: decoded,
    owner: target.owner,
    path: target.path,
    chain: target.chain,
  })
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
  let owners = report.diagnostic_resources()
  for i, d in report.diagnostics() {
    let ref_finding = d.code() == @exact.UnresolvedReference ||
      d.code() == @exact.InvalidReference ||
      d.code() == @exact.ConflictingIdentifier ||
      unavailable(d.code()) ||
      (d.code() == @exact.UnsupportedCheck && d.path().last() == Some("$ref"))
    add(
      self.findings,
      d.code(),
      d.message(),
      d.path(),
      if ref_finding {
        References
      } else {
        SchemaDocument
      },
      severity=if d.code() == @exact.UnsupportedCheck ||
        d.code() == @exact.UnsupportedDialect ||
        unavailable(d.code()) {
        Information
      } else {
        Error
      },
      resource=owners.get(i).unwrap_or(owner),
    )
  }
  if !report.is_complete() && report.diagnostics().is_empty() {
    add(
      self.findings,
      @exact.UnsupportedCheck,
      "Schema checks incomplete",
      path,
      SchemaDocument,
      severity=Information,
      resource=owner,
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
  chain~ : Array[Site] = [],
) -> Unit {
  let limits = self.limits
  guard self.typed(
      value,
      owner,
      path,
      "example pairing",
      (v, p) => pairing_(v, p, limits),
      chain~,
    )
    is Some(pairing) else {
    return
  }
  if !self.checked.add_and_check("pairing " + site_key(pairing.owner, pairing.path)) {
    return
  }
  self.fields(
    ExamplePairingObject,
    pairing.value.value,
    pairing.owner,
    pairing.path,
    chain=pairing.chain,
  )
  let example = (v, p) => example_(v, p, limits)
  let at = pairing.path
  let examples = []
  if pairing.value.value.get("params") is Some(params) &&
    params.kind() is @exact.Array(items) {
    for i, item in items {
      examples.push(
        self.typed(
          item,
          pairing.owner,
          child(child(at, "params"), i.to_string()),
          "example",
          example,
          chain=pairing.chain,
        ),
      )
    }
  }
  if pairing.value.value.get("result") is Some(result) {
    examples.push(
      self.typed(
        result,
        pairing.owner,
        child(at, "result"),
        "example",
        example,
        chain=pairing.chain,
      ),
    )
  }
  for resolved in examples {
    if resolved is Some(target) {
      self.fields(
        ExampleObject,
        target.value.value,
        target.owner,
        target.path,
        chain=target.chain,
      )
    }
  }
}

///|
fn[T] Check::items(
  self : Check,
  method_ : Resolved[Method],
  name : String,
  kind : String,
  decode : (@exact.Value, Array[String]) -> T raise DecodeError,
) -> Array[Resolved[T]] {
  guard method_.value.value.get(name) is Some(raw) &&
    raw.kind() is @exact.Array(items) else {
    return []
  }
  let resolved = []
  for i, item in items {
    if self.typed(
        item,
        method_.owner,
        child(child(method_.path, name), i.to_string()),
        kind,
        decode,
        chain=method_.chain,
      )
      is Some(target) {
      resolved.push(target)
    }
  }
  resolved
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
  // A different registered value at the base conflicts with the input, which
  // stays authoritative for its own content; validate reports the conflict.
  let resources = match registered {
    Some(resource) => {
      let identity = resource.uri().identity()
      match
        @reference.ResourceSet::new(
          resources.resources().filter(r => r.uri().identity() != identity),
          root_base=resources.root_base(),
          limits=@exact.Limits::unlimited(),
        ) {
        Ok(set) => set
        Err(_) => resources
      }
    }
    None => resources
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
fn resource_key(resource : @reference.UriReference?) -> String {
  match resource {
    Some(uri) => uri.identity()
    None => ""
  }
}

///|
fn array_index(token : String) -> Bool {
  !token.is_empty() &&
  (token == "0" || !token.has_prefix("0")) &&
  token.code_units().iter().all(c => c >= 48 && c <= 57)
}

///|
/// Pointer tokens in document order: array indices numerically, other tokens
/// by UTF-16 code units, and a prefix before its extensions.
fn compare_paths(a : Array[String], b : Array[String]) -> Int {
  for i in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
    let x = a[i]
    let y = b[i]
    let order = if array_index(x) && array_index(y) && x.length() != y.length() {
      x.length().compare(y.length())
    } else {
      x.lexical_compare(y)
    }
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
fn compare_findings(a : Finding, b : Finding) -> Int {
  let order = resource_key(a.location.resource).lexical_compare(
    resource_key(b.location.resource),
  )
  if order != 0 {
    return order
  }
  let order = compare_paths(a.location.path, b.location.path)
  if order != 0 {
    return order
  }
  let order = a.diagnostic
    .code()
    .to_repr()
    .to_string()
    .lexical_compare(b.diagnostic.code().to_repr().to_string())
  if order != 0 {
    return order
  }
  let order = match (a.location.span, b.location.span) {
    (Some(x), Some(y)) => x.start().compare(y.start())
    (Some(_), None) => -1
    (None, Some(_)) => 1
    (None, None) => 0
  }
  if order != 0 {
    return order
  }
  a.diagnostic.message().lexical_compare(b.diagnostic.message())
}

///|
/// Turn drafts into findings: one per distinct problem, located in the input
/// source when known, ordered, and bounded by the finding limit. Truncated
/// phases get a `LimitExceeded` marker and become incomplete.
fn finish(
  drafts : Array[Draft],
  document : Document,
  owner : @reference.UriReference?,
  source_map : @exact.SourceMap?,
  profile : ValidationProfile,
  index_complete : Bool,
  limits : @exact.Limits,
) -> ValidationReport {
  let own = resource_key(owner)
  let locate = (site : Site) => {
    let mut span = None
    let mut source_id = None
    if resource_key(site.resource) == own && source_map is Some(map) {
      if map.locations(site.path) is [first, ..] {
        span = Some(first.value_span())
        source_id = first.source_id()
      }
    }
    FindingLocation::{ resource: site.resource, path: site.path, span, source_id }
  }
  let version = document.version
  let unique : Array[Finding] = []
  let seen : Set[String] = Set([])
  for d in drafts {
    let key = resource_key(d.site.resource) +
      "|" +
      d.phase.to_repr().to_string() +
      "|" +
      d.severity.to_repr().to_string() +
      "|" +
      d.diagnostic.code().to_repr().to_string() +
      "|" +
      site_key(None, d.site.path) +
      "|" +
      d.diagnostic.message()
    if !seen.add_and_check(key) {
      continue
    }
    let location = locate(d.site)
    unique.push({
      diagnostic: @exact.Diagnostic::new(
        d.diagnostic.code(),
        d.diagnostic.message(),
        path=d.site.path,
        span=location.span,
      ),
      severity: d.severity,
      phase: d.phase,
      location,
      related: d.related.map(locate),
      chain: d.chain.map(locate),
      expected: d.expected,
      discrepancy: d.discrepancy,
      version,
      profile,
    })
  }
  unique.sort_by(compare_findings)
  let marker = (phase, message) => Finding::{
    diagnostic: @exact.Diagnostic::new(@exact.LimitExceeded, message),
    severity: Information,
    phase,
    location: { resource: None, path: [], span: None, source_id: None },
    related: [],
    chain: [],
    expected: None,
    discrepancy: None,
    version,
    profile,
  }
  // A facet with a computed error stays failed even if truncation drops it.
  let failed = [Model, SchemaDocument, References, Normative, Artifact].filter(phase => {
    unique.any(f => {
      f.phase == phase &&
      f.severity == Error &&
      f.diagnostic.code() != @exact.LimitExceeded
    })
  })
  let max = limits.max_findings()
  let findings = if unique.length() > max {
    unique[:if max < 0 { 0 } else { max }].to_owned()
  } else {
    unique
  }
  let truncated : Array[Phase] = []
  for f in unique[findings.length():] {
    if !truncated.contains(f.phase) {
      truncated.push(f.phase)
    }
  }
  for phase in [Model, SchemaDocument, References, Normative, Artifact] {
    if truncated.contains(phase) {
      findings.push(
        marker(
          phase,
          "Finding limit max_findings=\{max} exceeded; later findings were omitted",
        ),
      )
    }
  }
  if !index_complete {
    findings.push(marker(References, "Reference index is incomplete"))
  }
  findings.sort_by(compare_findings)
  let facet = phase => if failed.contains(phase) {
    Failed
  } else {
    coverage(findings, phase)
  }
  {
    profile,
    version,
    model: facet(Model),
    schemas: facet(SchemaDocument),
    references: facet(References),
    normative: facet(Normative),
    artifact: facet(Artifact),
    findings,
  }
}

///|
/// Validate a document against explicit resources. `base` is the document's
/// retrieval URI; relative references and schema identifiers need it. Nothing
/// is fetched. Unsupplied resources leave reference coverage incomplete. A
/// `source_map` from reading the same document adds spans to its findings.
pub fn validate(
  document : Document,
  profile~ : ValidationProfile = Specification,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
  base~ : @reference.UriReference? = None,
  source_map~ : @exact.SourceMap? = None,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> ValidationReport {
  let findings : Array[Draft] = []
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
  if base is Some(uri) &&
    resources.get(uri) is Some(registered) &&
    !(registered.value().equals(document.value, limits~) is Ok(true)) {
    add(
      findings,
      @exact.ConflictingIdentifier,
      "Base URI names a registered resource with different content; the input document is used",
      [],
      References,
    )
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
  let check = Check::{
    index,
    findings,
    checked: Set([]),
    limits,
    version: document.version,
    profile,
    links: [],
  }
  let root = document.value
  check.fields(DocumentObject, root, owner, [])
  let info = document.info
  check.fields(InfoObject, info.value, owner, ["info"])
  if info.contact() is Some(contact) {
    check.fields(ContactObject, contact.value, owner, ["info", "contact"])
  }
  if info.license() is Some(license) {
    check.fields(LicenseObject, license.value, owner, ["info", "license"])
    check.named(
      license.name(),
      owner,
      ["info", "license"],
      "License",
      discrepancy=Some(LicenseNameOmitted),
    )
  }
  check.external_docs(document.external_docs(), owner, [])
  check.servers(document.servers(), owner, ["servers"])
  if root.get("$schema") is Some(value) && value.text() is None {
    add(
      findings,
      @exact.WrongType,
      "Root $schema must be a string",
      ["$schema"],
      Model,
      resource=owner,
    )
  }
  let raw_methods = match root.get("methods") {
    Some(raw) =>
      match raw.kind() {
        @exact.Array(items) => items
        _ => []
      }
    None => []
  }
  let method_decoder = (v, p) => {
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
  }
  let methods = []
  let errors = []
  let mut methods_complete = true
  for i, raw_method in raw_methods {
    guard check.typed(
        raw_method,
        owner,
        ["methods", i.to_string()],
        "method",
        method_decoder,
      )
      is Some(method_) else {
      methods_complete = false
      continue
    }
    methods.push(method_)
    let chain = method_.chain
    check.fields(
      MethodObject,
      method_.value.value,
      method_.owner,
      method_.path,
      chain~,
    )
    check.external_docs(
      method_.value.external_docs(),
      method_.owner,
      method_.path,
      chain~,
    )
    check.servers(
      method_.value.servers(),
      method_.owner,
      child(method_.path, "servers"),
      chain~,
    )
    let param_names : Map[String, Array[Site]] = Map([])
    let mut optional_seen = false
    let raw_params = match method_.value.value.get("params") {
      Some(raw) =>
        match raw.kind() {
          @exact.Array(items) => items
          _ => []
        }
      None => []
    }
    for pi, raw_param in raw_params {
      let param_path = child(child(method_.path, "params"), pi.to_string())
      guard check.typed(
          raw_param,
          method_.owner,
          param_path,
          "content descriptor",
          descriptor_decoder(limits),
          chain~,
        )
        is Some(desc) else {
        continue
      }
      check.fields(
        ContentDescriptorObject,
        desc.value.value,
        desc.owner,
        desc.path,
        chain=desc.chain,
      )
      let param_site = Site::{
        resource: desc.owner,
        path: child(desc.path, "name"),
      }
      match param_names.get(desc.value.name) {
        Some(first) =>
          check.normative(
            @exact.DuplicateName,
            "Parameter names must be unique",
            param_site,
            chain=desc.chain,
            related=first,
          )
        None => param_names[desc.value.name] = [param_site, ..desc.chain]
      }
      let required = desc.value.required.unwrap_or(false)
      if required && optional_seen {
        check.normative(
          @exact.ParameterOrder,
          "Optional parameters precede a required parameter",
          { resource: method_.owner, path: param_path },
          chain~,
          discrepancy=Some(OptionalParameterBeforeRequired),
        )
      }
      if !required {
        optional_seen = true
      }
      check.schema(desc.value.schema, desc.owner, child(desc.path, "schema"))
    }
    if method_.value.value.get("result") is Some(raw_result) {
      if check.typed(
          raw_result,
          method_.owner,
          child(method_.path, "result"),
          "content descriptor",
          descriptor_decoder(limits),
          chain~,
        )
        is Some(desc) {
        check.fields(
          ContentDescriptorObject,
          desc.value.value,
          desc.owner,
          desc.path,
          chain=desc.chain,
        )
        check.schema(desc.value.schema, desc.owner, child(desc.path, "schema"))
      }
    }
    let method_errors = check.items(method_, "errors", "error", (v, p) => {
      error_object_(v, p, limits)
    })
    for error in method_errors {
      check.fields(
        ErrorObjectKind,
        error.value.value,
        error.owner,
        error.path,
        chain=error.chain,
      )
    }
    errors.push(method_errors)
    for link in check.items(method_, "links", "link", (v, p) => {
      link_(v, p, limits)
    }) {
      check.link(link.value, link.owner, link.path, chain=link.chain)
    }
    for tag in check.items(method_, "tags", "tag", (v, p) => tag_(v, p, limits)) {
      check.tag(tag.value, tag.owner, tag.path, chain=tag.chain)
    }
    if method_.value.value.get("examples") is Some(raw) &&
      raw.kind() is @exact.Array(items) {
      for ei, item in items {
        check.pairing(
          item,
          method_.owner,
          child(child(method_.path, "examples"), ei.to_string()),
          chain~,
        )
      }
    }
  }
  if root.get("components") is Some(components) {
    match components.kind() {
      @exact.Object(_) => {
        check.fields(ComponentsObject, components, owner, ["components"])
        if components.get("schemas") is Some(schemas) {
          match schemas.kind() {
            @exact.Object(entries) =>
              for (name, value) in entries {
                let path = ["components", "schemas", name]
                match @schema.Schema::from_json(value, limits~) {
                  Ok(schema) => check.schema(schema, owner, path)
                  Err(d) =>
                    add(
                      findings,
                      d.code(),
                      d.message(),
                      [..path, ..d.path()],
                      SchemaDocument,
                      resource=owner,
                    )
                }
              }
            _ =>
              add(
                findings,
                @exact.WrongType,
                "Schema components must be an object",
                ["components", "schemas"],
                Model,
                resource=owner,
              )
          }
        }
        if document.components is Some(typed) {
          check.component_keys(typed, owner)
          let at = (table, key : ComponentKey) => {
            ["components", table, key.to_string()]
          }
          for entry in typed.content_descriptors().unwrap_or([]) {
            let path = at("contentDescriptors", entry.0)
            check.fields(ContentDescriptorObject, entry.1.value, owner, path)
            check.schema(entry.1.schema(), owner, child(path, "schema"))
          }
          for entry in typed.examples().unwrap_or([]) {
            check.fields(ExampleObject, entry.1.value, owner, at("examples", entry.0))
          }
          for entry in typed.links().unwrap_or([]) {
            check.link(entry.1, owner, at("links", entry.0))
          }
          for entry in typed.errors().unwrap_or([]) {
            check.fields(ErrorObjectKind, entry.1.value, owner, at("errors", entry.0))
          }
          for entry in typed.tags().unwrap_or([]) {
            check.tag(entry.1, owner, at("tags", entry.0))
          }
          for entry in typed.example_pairings().unwrap_or([]) {
            check.pairing(entry.1.value, owner, at("examplePairings", entry.0))
          }
          for entry in typed.example_pairing_objects().unwrap_or([]) {
            check.pairing(
              entry.1.value,
              owner,
              at("examplePairingObjects", entry.0),
            )
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
          resource=owner,
        )
    }
  }
  check.uniqueness(methods, errors, methods_complete~)
  check.artifact(document, owner)
  finish(
    findings,
    document,
    owner,
    source_map,
    profile,
    index.complete(),
    limits,
  )
}

///|
pub fn validate_closed(
  document : Document,
  profile~ : ValidationProfile = Specification,
  resources~ : @reference.ResourceSet = @reference.ResourceSet::empty(),
  base~ : @reference.UriReference? = None,
  source_map~ : @exact.SourceMap? = None,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> ClosedValidation {
  let report = validate(
    document,
    profile~,
    resources~,
    base~,
    source_map~,
    limits~,
  )
  // Specification gates on normative rules and keeps artifact results as
  // information. Compatibility gates on the artifact; its normative facet
  // passes only when every error was a listed discrepancy (now a warning).
  let passed = report.model == Passed &&
    report.schemas == Passed &&
    report.references == Passed &&
    report.normative == Passed &&
    (profile == Specification || report.artifact == Passed)
  {
    report,
    document: if passed {
      Some({
        document,
        report,
        resources: resources.resources().map(r => r.uri()),
      })
    } else {
      None
    },
  }
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
pub extend FindingLocation with @debug.Debug::{to_repr}

///|
pub extend ValidationReport with @debug.Debug::{to_repr}

///|
pub extend ValidatedDocument with @debug.Debug::{to_repr}

///|
pub extend ClosedValidation with @debug.Debug::{to_repr}
