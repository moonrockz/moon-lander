///|
/// One pinned-artifact violation, relative to the document root.
priv struct Violation {
  code : @exact.Code
  message : String
  path : Array[String]
  expected : String?
}

///|
/// The pinned metaschema for a supported version, parsed from the generated
/// pruned copy. Generation proves every keyword in it is interpreted here.
fn artifact_schema(version : DocumentVersion) -> @exact.Value {
  let text = if legacy(version) { artifact_1_3_2 } else { artifact_1_4 }
  let limits = @exact.Limits::unlimited()
  match @exact.parse(text, limits~) {
    Ok(cst) =>
      match cst.lower() {
        Ok(value) => value
        Err(_) => abort("Generated artifact schema invariant")
      }
    Err(_) => abort("Generated artifact schema invariant")
  }
}

///|
/// The three patterns the generator admits, as fixed matchers.
fn pattern_matches(pattern : String, text : String) -> Bool {
  match pattern {
    "^x-" => text.has_prefix("x-")
    "[0-z]+" => text.code_units().iter().any(c => c >= 48 && c <= 122)
    "^1\\.4\\.\\d+$" => {
      guard text.has_prefix("1.4.") && text.length() > 4 else { return false }
      text[4:].code_units().iter().all(c => c >= 48 && c <= 57)
    }
    _ => abort("Generated artifact pattern invariant")
  }
}

///|
fn type_matches(name : String, value : @exact.Value) -> Bool {
  match (name, value.kind()) {
    ("object", @exact.Object(_)) => true
    ("array", @exact.Array(_)) => true
    ("string", @exact.String(_)) => true
    ("boolean", @exact.Boolean(_)) => true
    ("null", @exact.Null) => true
    ("number", @exact.Numeric(_)) => true
    ("integer", @exact.Numeric(n)) => n.is_integer()
    _ => false
  }
}

///|
fn code_points(text : String) -> Int {
  let mut count = 0
  for _ in text {
    count += 1
  }
  count
}

///|
/// Evaluate the draft-07 subset used by the pinned metaschemas. Work is an
/// explicit stack; only `oneOf` evaluates branches separately, and its
/// nesting depth is fixed by the schema, not by the document.
fn evaluate(
  root : @exact.Value,
  schema : @exact.Value,
  value : @exact.Value,
  path : Array[String],
) -> Array[Violation] {
  let out = []
  let stack = [(schema, value, path)]
  while stack.pop() is Some((schema, value, path)) {
    let fail = (code, message, expected) => {
      out.push({ code, message, path, expected })
    }
    match schema.kind() {
      @exact.Boolean(true) => continue
      @exact.Boolean(false) => {
        fail(@exact.InvalidValue, "No value is allowed here", None)
        continue
      }
      _ => ()
    }
    if schema.get("$ref").bind(r => r.text()) is Some(target) {
      if target.has_prefix("#/definitions/") {
        match root.get("definitions").bind(d => d.get(target[14:].to_owned())) {
          Some(definition) => stack.push((definition, value, path))
          None => abort("Generated artifact reference invariant")
        }
      } else if target == "https://meta.json-schema.tools" {
        // Keyword validity is the schema-document facet's draft-07 check.
        if !(value.kind() is (@exact.Boolean(_) | @exact.Object(_))) {
          fail(@exact.WrongType, "Expected a boolean or object schema", None)
        }
      } else if value.text() is None {
        fail(@exact.WrongType, "Expected a reference string", None)
      }
      continue
    }
    if schema.get("type") is Some(expected) {
      let names = match expected.kind() {
        @exact.String(name) => [name]
        @exact.Array(items) => items.filter_map(item => item.text())
        _ => []
      }
      if !names.iter().any(name => type_matches(name, value)) {
        fail(@exact.WrongType, "Expected " + names.join(" or "), None)
        continue
      }
    }
    if schema.get("enum") is Some(allowed) && allowed.kind() is @exact.Array(items) {
      let limits = @exact.Limits::unlimited()
      if !items.iter().any(item => item.equals(value, limits~) is Ok(true)) {
        fail(@exact.InvalidValue, "Value is not one of the allowed values", None)
      }
    }
    if value.text() is Some(text) {
      if schema.get("pattern").bind(p => p.text()) is Some(pattern) &&
        !pattern_matches(pattern, text) {
        fail(@exact.InvalidValue, "Value does not match " + pattern, None)
      }
      if schema.get("minLength") is Some(minimum) &&
        minimum.kind() is @exact.Numeric(n) &&
        n.numeric_compare(@exact.Number::parse(code_points(text).to_string()).unwrap()) >
        0 {
        fail(@exact.InvalidValue, "Value is shorter than the minimum length", None)
      }
    }
    if schema.get("oneOf") is Some(branches) &&
      branches.kind() is @exact.Array(branches) {
      let results = branches.map(branch => evaluate(root, branch, value, path))
      let passed = results.filter(r => r.is_empty()).length()
      if passed > 1 {
        fail(@exact.InvalidValue, "Value matches more than one alternative", None)
      } else if passed == 0 {
        // Report the alternative the value was written as: a reference when
        // it has `$ref`, otherwise the object alternative.
        let reference = value.get("$ref") is Some(_)
        let chosen = branches.search_by(branch => {
          let to_reference = branch
            .get("$ref")
            .bind(r => r.text())
            .map(t => t == "#/definitions/referenceObject")
            .unwrap_or(false)
          to_reference == reference
        })
        out.append(results[chosen.unwrap_or(0)])
      }
    }
    match value.kind() {
      @exact.Object(fields) => {
        if schema.get("required") is Some(required) &&
          required.kind() is @exact.Array(names) {
          for name in names {
            if name.text() is Some(name) && value.get(name) is None {
              fail(@exact.MissingField, "Missing required field " + name, Some(name))
            }
          }
        }
        let properties = schema.get("properties")
        let patterns = match schema.get("patternProperties").map(p => p.kind()) {
          Some(@exact.Object(entries)) => entries
          _ => []
        }
        let additional = schema.get("additionalProperties")
        for i in 0..<fields.length() {
          let (name, item) = fields[fields.length() - 1 - i]
          let at = child(path, name)
          let mut matched = false
          if properties.bind(p => p.get(name)) is Some(property) {
            matched = true
            stack.push((property, item, at))
          }
          for entry in patterns {
            if pattern_matches(entry.0, name) {
              matched = true
              stack.push((entry.1, item, at))
            }
          }
          if !matched && additional is Some(additional) {
            match additional.kind() {
              @exact.Boolean(false) =>
                out.push({
                  code: @exact.UnknownField,
                  message: "Field is not allowed by the pinned metaschema",
                  path: at,
                  expected: None,
                })
              _ => stack.push((additional, item, at))
            }
          }
        }
      }
      @exact.Array(items) =>
        if schema.get("items") is Some(each) {
          for i in 0..<items.length() {
            let index = items.length() - 1 - i
            stack.push((each, items[index], child(path, index.to_string())))
          }
        }
      _ => ()
    }
  }
  out
}

///|
/// Check the document's own JSON against its version's pinned metaschema.
/// External resources are not documents and are not artifact-checked.
fn Check::artifact(
  self : Check,
  document : Document,
  owner : @reference.UriReference?,
) -> Unit {
  let schema = artifact_schema(document.version)
  for v in evaluate(schema, schema, document.value, []) {
    add(
      self.findings,
      v.code,
      v.message,
      v.path,
      Artifact,
      resource=owner,
      expected=v.expected,
    )
  }
}
