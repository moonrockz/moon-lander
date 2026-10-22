///|
priv struct SchemaCheck {
  findings : Array[@json.Diagnostic]
  owners : Array[@reference.UriReference?]
  mut owner : @reference.UriReference?
  max_findings : Int32
  mut complete : Bool
  mut stopped : Bool
  mut comparison_work : Int32
}

///|
fn SchemaCheck::emit(self : SchemaCheck, d : @json.Diagnostic) -> Unit {
  if self.stopped {
    return
  }
  if d.code() == @json.LimitExceeded {
    self.complete = false
  }
  if self.findings.length() < self.max_findings {
    self.findings.push(d)
    self.owners.push(self.owner)
  } else {
    let limit = @json.Diagnostic::new(
      @json.LimitExceeded,
      "Schema finding limit exceeded",
    )
    if self.findings.is_empty() {
      self.findings.push(limit)
      self.owners.push(self.owner)
    } else {
      self.findings[self.findings.length() - 1] = limit
    }
    self.complete = false
    self.stopped = true
  }
}

///|
fn SchemaCheck::exhaust(
  self : SchemaCheck,
  message : String,
  path : SchemaPath,
) -> Unit {
  self.emit(
    @json.Diagnostic::new(@json.LimitExceeded, message, path=path_tokens(path)),
  )
  self.complete = false
  self.stopped = true
}

///|
fn SchemaCheck::pattern(
  self : SchemaCheck,
  source : String,
  path : SchemaPath,
  limits : @json.Limits,
) -> Unit {
  match check_pattern(source, limits~) {
    Ok(_) => ()
    Err(error) => {
      self.emit(
        @json.Diagnostic::new(
          error.code(),
          error.message() +
          " at decoded-pattern UTF-16 offset " +
          error.offset().to_string(),
          path=path_tokens(path),
        ),
      )
      if error.code() == @json.LimitExceeded {
        self.complete = false
      }
    }
  }
}

///|
fn SchemaCheck::enum_unique(
  self : SchemaCheck,
  items : Array[@json.Value],
  path : SchemaPath,
  limits : @json.Limits,
) -> Unit {
  let sizes = []
  for item in items {
    match @json.write(item, limits~) {
      Ok(text) => sizes.push(text.length())
      Err(d) => {
        self.emit(with_path(d, path))
        self.complete = false
        return
      }
    }
  }
  for i in 0..<items.length() {
    for j in 0..<i {
      if sizes[i] > self.comparison_work ||
        sizes[j] > self.comparison_work - sizes[i] {
        self.exhaust("Schema enum comparison work limit exceeded", path)
        return
      }
      self.comparison_work -= sizes[i] + sizes[j]
      match items[i].equals(items[j], numeric=true, limits~) {
        Ok(true) => {
          self.emit(
            invalid(
              "Enum values must be mathematically unique",
              path=path_tokens(path, suffix=[i.to_string()]),
            ),
          )
          break
        }
        Ok(false) => ()
        Err(d) => {
          self.emit(with_path(d, path))
          self.complete = false
          return
        }
      }
    }
    if self.stopped {
      return
    }
  }
}

///|
fn retrieval_base_valid(base : @reference.UriReference) -> Bool {
  base.is_absolute() && base.fragment() is None
}

///|
fn pointer_key(key : String?, token : String) -> String? {
  match key {
    Some(key) =>
      Some(
        key + "/" + token.replace(old="~", new="~0").replace(old="/", new="~1"),
      )
    None => None
  }
}

///|
fn check_schema(
  value : @json.Value,
  root : @json.Value,
  path : Array[String],
  base : @reference.UriReference?,
  resources : @reference.ResourceSet,
  max_nodes : Int32,
  max_edges : Int32,
  max_findings : Int32,
  max_comparison_work : Int32,
  limits : @json.Limits,
) -> Report {
  let state = new_check(max_findings, max_comparison_work, limits)
  let mut references_complete = true
  let mut initial = RootPath
  for token in path {
    initial = PathStep(initial, token)
  }
  if base is Some(base) && !retrieval_base_valid(base) {
    state.emit(
      @json.Diagnostic::new(
        @json.InvalidReference,
        "Schema retrieval base must be absolute and fragment-free",
      ),
    )
    return {
      findings: state.findings,
      complete: false,
      references_complete: false,
      resolutions: [],
      owners: state.owners,
    }
  }
  let pointer = match @reference.JsonPointer::from_tokens(path, limits~) {
    Ok(pointer) => pointer
    Err(d) => {
      state.emit(with_path(d, initial))
      return {
        findings: state.findings,
        complete: false,
        references_complete: false,
        resolutions: [],
        owners: state.owners,
      }
    }
  }
  // A registered base names the physical document; otherwise `root` is the
  // caller's input document under the optional base.
  let registered = match base {
    Some(base) => resources.get(base)
    None => None
  }
  let index = match registered {
    Some(resource) => {
      let roots = resource.schema_roots()
      if pointer.resolve(resource.value(), limits~) is Ok(_) {
        roots.push(pointer)
      }
      let trusted = @json.Limits::unlimited()
      let replaced = @reference.Resource::new(
        resource.uri(),
        resource.value(),
        aliases=resource.aliases(),
        schema_roots=roots,
        limits=trusted,
      )
      match replaced {
        Ok(replaced) => {
          let identity = resource.uri().identity()
          let all = resources
            .resources()
            .map(r => if r.uri().identity() == identity { replaced } else { r })
          match
            @reference.ResourceSet::new(
              all,
              root_base=resources.root_base(),
              limits=trusted,
            ) {
            Ok(set) => @reference.SchemaIndex::new(set, limits~)
            Err(_) => @reference.SchemaIndex::new(resources, limits~)
          }
        }
        Err(_) => @reference.SchemaIndex::new(resources, limits~)
      }
    }
    None =>
      @reference.SchemaIndex::new(
        resources,
        input=Some(root),
        input_base=base,
        // The submitted path is advisory when it is absent from `root`.
        input_roots=if pointer.resolve(root, limits~) is Ok(_) {
          [pointer]
        } else {
          []
        },
        limits~,
      )
  }
  for d in index.diagnostics() {
    state.emit(d)
  }
  if !index.complete() {
    references_complete = false
  }
  let document = match registered {
    Some(resource) => Some(resource.uri())
    None => base
  }
  walk_schema(
    state,
    value,
    Some(root),
    initial,
    pointer,
    document,
    index,
    references_complete,
    max_nodes,
    max_edges,
    limits,
  )
}

///|
fn new_check(
  max_findings : Int32,
  max_comparison_work : Int32,
  limits : @json.Limits,
) -> SchemaCheck {
  {
    findings: [],
    owners: [],
    owner: None,
    max_findings: if max_findings < limits.max_findings() {
      max_findings
    } else {
      limits.max_findings()
    },
    complete: true,
    stopped: false,
    comparison_work: max_comparison_work,
  }
}

///|
fn walk_schema(
  state : SchemaCheck,
  value : @json.Value,
  root : @json.Value?,
  initial : SchemaPath,
  pointer : @reference.JsonPointer,
  document : @reference.UriReference?,
  index : @reference.SchemaIndex,
  references_complete : Bool,
  max_nodes : Int32,
  max_edges : Int32,
  limits : @json.Limits,
) -> Report {
  let resolutions : Array[@reference.Resolution] = []
  let mut references_complete = references_complete
  let mut root_checked = root is None
  if max_nodes < 1 {
    state.exhaust("Schema traversal limit exceeded", initial)
  }
  match @json.write(value, limits~) {
    Ok(_) => ()
    Err(d) => {
      state.emit(with_path(d, initial))
      state.complete = false
      state.stopped = true
    }
  }
  // The submitted schema keeps the physical identity at `path` only when it is
  // exactly the value there; otherwise it is checked as a separate input.
  let (scope, key) = match index.locate(document, pointer, limits~) {
    Ok(location) if location.target().equals(value, limits~) is Ok(true) =>
      (index.scope(location), Some(location.identity()))
    _ => (document, None)
  }
  let stack = [(value, initial, scope, key, false, document)]
  state.owner = document
  let mut reserved = 1
  let mut edges = 0
  let visited : Set[String] = Set([])
  while !state.stopped &&
        stack.pop() is Some((current, path, scope, key, scoped, owner)) {
    state.owner = owner
    if key is Some(key) && !visited.add_and_check(key) {
      continue
    }
    // An indexed location carries its scope, including its own `$id`;
    // otherwise the walker applies the node's `$id` itself.
    let (scope, scoped) = match key {
      Some(key) =>
        match index.indexed_scope(key) {
          Some(indexed) => (indexed, true)
          None => (scope, scoped)
        }
      None => (scope, scoped)
    }
    guard current.kind() is @json.Object(fields) else {
      if !schema_kind(current) {
        state.emit(
          invalid(
            "Expected an object or boolean schema",
            path=path_tokens(path),
          ),
        )
      }
      continue
    }
    if current.get("$schema") is Some(declaration) {
      match decode_keyword("$schema", declaration, limits~) {
        Ok(Dialect(ref_)) =>
          if !draft07(ref_.text()) {
            state.emit(
              @json.Diagnostic::new(
                @json.UnsupportedDialect,
                "Only draft-07 is supported",
                path=path_tokens(PathStep(path, "$schema")),
              ),
            )
            state.complete = false
            continue
          }
        Ok(_) => abort("Dialect decoding invariant")
        Err(d) => state.emit(with_path(d, PathStep(path, "$schema")))
      }
    }
    if current.get("$ref") is Some(ref_value) {
      let at = PathStep(path, "$ref")
      let reference = match decode_keyword("$ref", ref_value, limits~) {
        Ok(Ref(ref_)) => ref_
        Ok(_) => abort("Reference decoding invariant")
        Err(d) => {
          state.emit(with_path(d, at))
          continue
        }
      }
      if edges >= max_edges {
        state.exhaust("Schema reference edge limit exceeded", at)
        break
      }
      edges += 1
      if !root_checked && root is Some(root) {
        match @json.write(root, limits~) {
          Err(d) => {
            state.emit(d)
            state.complete = false
            state.stopped = true
            break
          }
          Ok(_) => root_checked = true
        }
      }
      let resolution = index.resolve(reference, base=scope, limits~)
      resolutions.push(resolution)
      if !resolution.complete() {
        references_complete = false
      }
      guard resolution.target() is Some(target) else {
        for d in resolution.diagnostics() {
          state.emit(
            @json.Diagnostic::new(d.code(), d.message(), path=path_tokens(at)),
          )
        }
        continue
      }
      if !schema_kind(target.target()) {
        state.emit(
          @json.Diagnostic::new(
            @json.WrongType,
            "Reference target must be an object or boolean schema",
            path=path_tokens(at),
          ),
        )
        continue
      }
      if !visited.contains(target.identity()) {
        let mut target_path = RootPath
        for token in target.pointer().tokens() {
          target_path = PathStep(target_path, token)
        }
        if reserved >= max_nodes {
          state.exhaust("Schema traversal limit exceeded", at)
          break
        }
        reserved += 1
        stack.push(
          (
            target.target(),
            target_path,
            target.resource(),
            Some(target.identity()),
            false,
            target.resource(),
          ),
        )
      }
      continue
    }
    let scope = if scoped {
      scope
    } else {
      match current.get("$id") {
        Some(id) =>
          match decode_keyword("$id", id, limits~) {
            Ok(Id(id)) => @reference.schema_scope(id, scope, limits~)
            _ => scope
          }
        None => scope
      }
    }
    fields.sort_by((a, b) => a.0.lexical_compare(b.0))
    let children = []
    for (name, item) in fields {
      if state.stopped {
        break
      }
      if !all_names.contains(name) {
        continue
      }
      let at = PathStep(path, name)
      match decode_keyword(name, item, limits~) {
        Err(d) => state.emit(with_path(d, at))
        Ok(Enum(items)) => state.enum_unique(items, at, limits)
        Ok(Pattern(source)) => state.pattern(source, at, limits)
        Ok(_) => ()
      }
      if name == "patternProperties" && item.kind() is @json.Object(entries) {
        entries.sort_by((a, b) => a.0.lexical_compare(b.0))
        for (pattern, _) in entries {
          state.pattern(pattern, PathStep(at, pattern), limits)
        }
      }
      for entry in @domain.draft07_subschemas(name, item) {
        if reserved >= max_nodes {
          state.exhaust("Schema traversal limit exceeded", at)
          break
        }
        reserved += 1
        let mut child_path = at
        let mut child_key = pointer_key(key, name)
        for token in entry.0 {
          child_path = PathStep(child_path, token)
          child_key = pointer_key(child_key, token)
        }
        children.push((entry.1, child_path, scope, child_key, false, owner))
      }
    }
    for i in 0..<children.length() {
      stack.push(children[children.length() - 1 - i])
    }
  }
  {
    findings: state.findings,
    complete: state.complete && references_complete,
    references_complete,
    resolutions,
    owners: state.owners,
  }
}

///|
/// Check one schema against an index the caller built once for a whole
/// document. `resource` names the index document holding the schema (None for
/// the unnamed input) and `path` is its location there. Index diagnostics are
/// the caller's to report.
pub fn validate_in(
  schema : Schema,
  index~ : @reference.SchemaIndex,
  resource~ : @reference.UriReference? = None,
  path~ : Array[String] = [],
  max_nodes~ : Int32 = 10000,
  max_edges~ : Int32 = 4096,
  max_findings~ : Int32 = 256,
  max_comparison_work~ : Int32 = 1000000,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Report {
  let state = new_check(max_findings, max_comparison_work, limits)
  let mut initial = RootPath
  for token in path {
    initial = PathStep(initial, token)
  }
  let pointer = match @reference.JsonPointer::from_tokens(path, limits~) {
    Ok(pointer) => pointer
    Err(d) => {
      state.emit(with_path(d, initial))
      return {
        findings: state.findings,
        complete: false,
        references_complete: false,
        resolutions: [],
        owners: state.owners,
      }
    }
  }
  walk_schema(
    state,
    schema.value,
    None,
    initial,
    pointer,
    resource,
    index,
    true,
    max_nodes,
    max_edges,
    limits,
  )
}
