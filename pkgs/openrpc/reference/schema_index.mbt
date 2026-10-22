///|
/// Draft-07 identifier scopes over declared schema roots. Indexing walks only
/// draft-07 subschema positions: literal keywords, unknown keywords, `$ref`
/// siblings and declared foreign dialects never establish identifiers.
/// The optional input is the caller's own document, named by `input_base`
/// when it has one, and is never registered as a resource.
pub struct SchemaIndex {
  priv resources : ResourceSet
  priv input : @json.Value?
  priv input_base : UriReference?
  priv ids : Map[String, Location]
  priv names : Map[String, Location]
  priv scopes : Map[String, UriReference?]
  priv diagnostics : Array[@json.Diagnostic]
  priv mut complete : Bool
  priv max_findings : Int32
} derive(Debug)

///|
pub extend SchemaIndex with @debug.Debug::{to_repr}

///|
fn SchemaIndex::report(
  self : SchemaIndex,
  d : @json.Diagnostic,
  complete~ : Bool = true,
) -> Unit {
  if !complete {
    self.complete = false
  }
  if self.diagnostics.length() < self.max_findings {
    self.diagnostics.push(d)
  } else {
    self.complete = false
  }
}

///|
/// Draft-07 core 8.2.3 plain-name fragments.
fn plain_name(text : String) -> Bool {
  let first = text.code_unit_at(0)
  if !uri_letter(first) {
    return false
  }
  for c in text.code_units() {
    if !(uri_letter(c) ||
      uri_digit(c) ||
      c == 45 ||
      c == 46 ||
      c == 58 ||
      c == 95) {
      return false
    }
  }
  true
}

///|
fn SchemaIndex::bind_id(
  self : SchemaIndex,
  scope : UriReference,
  location : Location,
) -> Bool {
  let identity = scope.identity()
  let owner = match self.ids.get(identity) {
    Some(existing) => Some(existing)
    None =>
      match self.resources.get(scope) {
        Some(resource) =>
          Some(Location::{
            resource: Some(resource.uri),
            pointer: { parts: [], },
            target: resource.value,
          })
        None =>
          match (self.input, self.input_base) {
            (Some(value), Some(base)) if base.identity() == identity =>
              Some(Location::{
                resource: Some(base),
                pointer: { parts: [], },
                target: value,
              })
            _ => None
          }
      }
  }
  if owner is Some(existing) && existing.identity() != location.identity() {
    self.report(
      @json.Diagnostic::new(
        @json.ConflictingIdentifier,
        "Schema identifier " +
        scope.text() +
        " already names " +
        existing.identity(),
        path=[..location.pointer.parts, "$id"],
      ),
    )
    return false
  }
  self.ids.set(identity, location)
  true
}

///|
fn SchemaIndex::bind_name(
  self : SchemaIndex,
  scope_root : String,
  name : String,
  location : Location,
) -> Unit {
  let key = scope_root + "#" + name
  match self.names.get(key) {
    Some(existing) if existing.identity() != location.identity() =>
      self.report(
        @json.Diagnostic::new(
          @json.ConflictingIdentifier,
          "Schema identifier fragment #" +
          name +
          " already names " +
          existing.identity(),
          path=[..location.pointer.parts, "$id"],
        ),
      )
    _ => self.names.set(key, location)
  }
}

///|
/// The scope after applying a draft-07 `$id` at `location`, with the identity
/// of the location that establishes it. Plain names are keyed by that
/// location, so every spelling of its document reaches them.
fn SchemaIndex::apply_id(
  self : SchemaIndex,
  id : UriReference,
  scope : UriReference?,
  scope_root : String,
  location : Location,
  limits : @json.Limits,
) -> (UriReference?, String) {
  let at = [..location.pointer.parts, "$id"]
  let mut next = scope
  let mut root = scope_root
  if !same_document(id) {
    let resolved = match scope {
      Some(base) if base.is_absolute() => id.resolve(base, limits~)
      _ => if id.is_absolute() { id.resolve(id, limits~) } else { Ok(id) }
    }
    match resolved {
      Ok(uri) => {
        let free = uri.without_fragment()
        // Without an absolute base a relative identifier names its location
        // only within the unnamed input; nested relative scopes stay unbound.
        let bindable = free.is_absolute() || scope is None
        if bindable && !self.bind_id(free, location) {
          return (scope, scope_root)
        }
        next = Some(free)
        root = location.identity()
      }
      Err(d) => {
        self.report(
          @json.Diagnostic::new(d.code(), d.message(), path=at),
          complete=d.code() != @json.LimitExceeded,
        )
        return (scope, scope_root)
      }
    }
  }
  match id.fragment {
    None => ()
    Some(fragment) if fragment.is_empty() => ()
    Some(fragment) if plain_name(fragment) =>
      self.bind_name(root, fragment, location)
    Some(fragment) =>
      self.report(
        @json.Diagnostic::new(
          @json.UnsupportedCheck,
          "Draft-07 does not define identifier fragment #" + fragment,
          path=at,
        ),
        complete=false,
      )
  }
  (next, root)
}

///|
pub fn SchemaIndex::new(
  resources : ResourceSet,
  input~ : @json.Value? = None,
  input_base~ : UriReference? = None,
  input_roots~ : Array[JsonPointer] = [],
  limits~ : @json.Limits = @json.Limits::new(),
) -> SchemaIndex {
  let index = SchemaIndex::{
    resources,
    input,
    input_base,
    ids: Map([]),
    names: Map([]),
    scopes: Map([]),
    diagnostics: [],
    complete: true,
    max_findings: limits.max_findings(),
  }
  let stack : Array[
    (@json.Value, UriReference?, Array[String], UriReference?, String),
  ] = []
  let roots = []
  for resource in resources.resources {
    for root in resource.schema_roots {
      roots.push((resource.value, Some(resource.uri), root))
    }
  }
  if input is Some(value) {
    if input_base is Some(base) {
      if retrieval_name(base, "Input base URI") is Err(d) {
        index.report(d, complete=false)
      } else if resources.get(base) is Some(_) {
        index.report(
          @json.Diagnostic::new(
            @json.ConflictingIdentifier,
            "Input base URI " + base.text() + " is a registered resource",
          ),
        )
      }
    }
    for root in input_roots {
      roots.push((value, input_base, root))
    }
  }
  // Ancestors first: a nested root reached by walking its ancestors inherits
  // their identifier scopes, whatever order the roots were declared in.
  roots.sort_by((a, b) => a.2.parts.length() - b.2.parts.length())
  for i in 0..<roots.length() {
    let (document, owner, root) = roots[roots.length() - 1 - i]
    let document_root = Location::{
      resource: owner,
      pointer: { parts: [], },
      target: document,
    }.identity()
    match root.resolve(document, limits~) {
      Ok(value) => stack.push((value, owner, root.parts, owner, document_root))
      Err(d) => index.report(d, complete=d.code() != @json.LimitExceeded)
    }
  }
  let mut nodes = 0
  // `$ref` sites found while walking; their targets are schema positions too.
  let pending : Array[(@json.Value, UriReference?)] = []
  let mut exhausted = false
  while !exhausted {
    while stack.pop() is Some((value, owner, tokens, scope, scope_root)) {
      nodes += 1
      if nodes > limits.max_nodes() || tokens.length() > limits.max_depth() {
        index.report(
          @json.Diagnostic::new(
            @json.LimitExceeded,
            "Schema identifier index limit exceeded",
            path=tokens,
          ),
          complete=false,
        )
        exhausted = true
        break
      }
      let location = Location::{
        resource: owner,
        pointer: { parts: tokens, },
        target: value,
      }
      let key = location.identity()
      if index.scopes.contains(key) {
        continue
      }
      index.scopes.set(key, scope)
      guard value.kind() is @json.Object(fields) else { continue }
      if value.get("$schema") is Some(dialect) &&
        dialect.text() is Some(text) &&
        !@domain.draft07_dialect(text) {
        continue
      }
      if value.get("$ref") is Some(raw) {
        pending.push((raw, scope))
        continue
      }
      let mut next = scope
      let mut next_root = scope_root
      if value.get("$id") is Some(raw) &&
        raw.text() is Some(text) &&
        UriReference::parse(text, limits~) is Ok(id) {
        let (applied, applied_root) = index.apply_id(
          id, scope, scope_root, location, limits,
        )
        next = applied
        next_root = applied_root
        index.scopes.set(key, next)
      }
      fields.sort_by((a, b) => a.0.lexical_compare(b.0))
      let children = []
      for field in fields {
        for entry in @domain.draft07_subschemas(field.0, field.1) {
          children.push(
            (entry.1, owner, [..tokens, field.0, ..entry.0], next, next_root),
          )
        }
      }
      for i in 0..<children.length() {
        stack.push(children[children.length() - 1 - i])
      }
    }
    // Index referenced schemas that no declared root reached, at their
    // document's scope, until no new target appears.
    while !exhausted && stack.is_empty() && pending.pop() is Some((raw, scope)) {
      guard raw.text() is Some(text) &&
        Reference::parse(text, limits~) is Ok(reference) else {
        continue
      }
      guard index.resolve(reference, base=scope, limits~).target()
        is Some(target) else {
        continue
      }
      if index.scopes.contains(target.identity()) {
        continue
      }
      match target.target.kind() {
        @json.Object(_) | @json.Boolean(_) => {
          let document_root = Location::{
            resource: target.resource,
            pointer: { parts: [], },
            target: target.target,
          }.identity()
          stack.push(
            (
              target.target,
              target.resource,
              target.pointer.parts,
              target.resource,
              document_root,
            ),
          )
        }
        _ => ()
      }
    }
    if stack.is_empty() {
      break
    }
  }
  index
}

///|
pub fn SchemaIndex::resources(self : SchemaIndex) -> ResourceSet {
  self.resources
}

///|
pub fn SchemaIndex::diagnostics(self : SchemaIndex) -> Array[@json.Diagnostic] {
  self.diagnostics.copy()
}

///|
/// False when identifiers could not all be indexed: missing bases, undefined
/// fragment forms or exhausted limits.
pub fn SchemaIndex::complete(self : SchemaIndex) -> Bool {
  self.complete
}

///|
/// The base URI in effect for the schema at `location`: its nearest `$id`
/// scope when indexed, otherwise its document's retrieval URI. A relative
/// result means the scope is undetermined for lack of an absolute base.
pub fn SchemaIndex::scope(
  self : SchemaIndex,
  location : Location,
) -> UriReference? {
  match self.scopes.get(location.identity()) {
    Some(scope) => scope
    None => location.resource
  }
}

///|
/// The scope recorded for the indexed schema whose `Location::identity` is
/// `identity`, or None when that location was not indexed.
pub fn SchemaIndex::indexed_scope(
  self : SchemaIndex,
  identity : String,
) -> UriReference?? {
  self.scopes.get(identity)
}

///|
fn same_document(uri : UriReference) -> Bool {
  uri.scheme is None &&
  uri.authority is None &&
  uri.path.is_empty() &&
  uri.query is None
}

///|
fn SchemaIndex::document(self : SchemaIndex, uri : UriReference) -> Location? {
  match self.ids.get(uri.identity()) {
    Some(location) => return Some(location)
    None => ()
  }
  match self.resources.get(uri) {
    Some(resource) =>
      return Some({
        resource: Some(resource.uri),
        pointer: { parts: [], },
        target: resource.value,
      })
    None => ()
  }
  match (self.input, self.input_base) {
    (Some(value), Some(base)) if base.identity() == uri.identity() =>
      Some({ resource: Some(base), pointer: { parts: [], }, target: value, })
    _ => None
  }
}

///|
/// Resolve a schema reference from a site whose scope is `base`. Without a
/// base, the input's base or else the set's root base applies; a
/// same-document reference in an unnamed input targets that input.
pub fn SchemaIndex::resolve(
  self : SchemaIndex,
  reference : Reference,
  base~ : UriReference? = None,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Resolution {
  let base = match base {
    Some(_) => base
    None =>
      if self.input is Some(_) {
        self.input_base
      } else {
        self.resources.root_base
      }
  }
  let fail = fn(chain, d : @json.Diagnostic, complete) {
    { target: None, chain, diagnostics: [d], complete, }
  }
  let absolute = if reference.uri.is_absolute() {
    Some(reference.uri.resolve(reference.uri, limits~))
  } else {
    match base {
      Some(base) if base.is_absolute() =>
        Some(reference.uri.resolve(base, limits~))
      Some(_) => None
      None => None
    }
  }
  let absolute = match absolute {
    Some(Ok(uri)) => Some(uri)
    Some(Err(d)) =>
      return fail(
        [{ site: None, reference, resolved: None, }],
        d,
        d.code() != @json.LimitExceeded,
      )
    None => None
  }
  let chain = [{ site: None, reference, resolved: absolute, }]
  let (document, key) = match absolute {
    Some(uri) => {
      let free = uri.without_fragment()
      (self.document(free), free.identity())
    }
    None =>
      match (base, self.input) {
        // A relative scope is known only within the unnamed input.
        (Some(relative), _) if same_document(reference.uri) =>
          match self.ids.get(relative.without_fragment().identity()) {
            Some(location) => (Some(location), relative.text())
            None =>
              return fail(
                chain,
                @json.Diagnostic::new(
                  @json.MissingBaseUri,
                  "Reference " +
                  reference.text() +
                  " is in a scope with no absolute base URI",
                ),
                false,
              )
          }
        (None, Some(value)) if same_document(reference.uri) =>
          (
            Some(Location::{
              resource: None,
              pointer: { parts: [], },
              target: value,
            }),
            "",
          )
        _ =>
          return fail(
            chain,
            @json.Diagnostic::new(
              @json.MissingBaseUri,
              "Relative reference " +
              reference.text() +
              " has no absolute base URI",
            ),
            false,
          )
      }
  }
  guard document is Some(document) else {
    return fail(
      chain,
      @json.Diagnostic::new(
        @json.UnavailableResource,
        "Schema resource " + key + " was not supplied",
      ),
      false,
    )
  }
  match reference.fragment {
    WholeResource =>
      { target: Some(document), chain, diagnostics: [], complete: true, }
    PointerFragment(pointer) => {
      let target = match pointer.resolve(document.target, limits~) {
        Ok(target) => target
        Err(d) => return fail(chain, d, d.code() != @json.LimitExceeded)
      }
      let combined = match
        JsonPointer::from_tokens(
          [..document.pointer.parts, ..pointer.parts],
          limits~,
        ) {
        Ok(combined) => combined
        Err(d) => return fail(chain, d, false)
      }
      {
        target: Some({ resource: document.resource, pointer: combined, target, }),
        chain,
        diagnostics: [],
        complete: true,
      }
    }
    IdentifierFragment(name) =>
      match self.names.get(document.identity() + "#" + name) {
        Some(location) =>
          { target: Some(location), chain, diagnostics: [], complete: true, }
        None =>
          fail(
            chain,
            @json.Diagnostic::new(
              @json.UnresolvedReference,
              "No schema identifier #" + name + " in " + key,
            ),
            true,
          )
      }
  }
}

///|
/// The scope in effect below a schema whose `$id` is `id`, given the
/// enclosing scope. Without an absolute base, a relative identifier gives a
/// relative scope: fragment-only references resolve within the location the
/// index bound to it, and other references report `MissingBaseUri`.
pub fn schema_scope(
  id : UriReference,
  scope : UriReference?,
  limits~ : @json.Limits = @json.Limits::new(),
) -> UriReference? {
  if same_document(id) {
    return scope
  }
  let resolved = match scope {
    Some(base) if base.is_absolute() => id.resolve(base, limits~)
    _ => if id.is_absolute() { id.resolve(id, limits~) } else { Ok(id) }
  }
  match resolved {
    Ok(uri) => Some(uri.without_fragment())
    Err(_) => scope
  }
}

///|
/// The physical location at `pointer` in a registered resource, or in the
/// input when `resource` is None or names the input base.
pub fn SchemaIndex::locate(
  self : SchemaIndex,
  resource : UriReference?,
  pointer : JsonPointer,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Location, @json.Diagnostic] {
  let document : Location? = match resource {
    None =>
      match self.input {
        Some(value) =>
          Some({ resource: None, pointer: { parts: [], }, target: value, })
        None => None
      }
    Some(uri) =>
      match self.resources.get(uri) {
        Some(found) =>
          Some({
            resource: Some(found.uri),
            pointer: { parts: [], },
            target: found.value,
          })
        None =>
          match (self.input, self.input_base) {
            (Some(value), Some(base)) if base.identity() ==
              uri.without_fragment().identity() =>
              Some({
                resource: Some(base),
                pointer: { parts: [], },
                target: value,
              })
            _ => None
          }
      }
  }
  guard document is Some(document) else {
    return Err(
      @json.Diagnostic::new(
        @json.UnavailableResource,
        "Schema document was not supplied",
      ),
    )
  }
  match pointer.resolve(document.target, limits~) {
    Ok(target) => Ok({ resource: document.resource, pointer, target, })
    Err(d) => Err(d)
  }
}
