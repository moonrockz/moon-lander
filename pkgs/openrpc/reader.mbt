///|
priv suberror DecodeError {
  DecodeError(@exact.Diagnostic)
} derive(Debug)

///|
fn object(
  value : @exact.Value,
  path : Array[String],
) -> Array[(String, @exact.Value)] raise DecodeError {
  match value.kind() {
    @exact.Object(fields) => fields
    _ =>
      raise DecodeError(
        @exact.Diagnostic::new(@exact.WrongType, "Expected an object", path~),
      )
  }
}

///|
fn field(
  value : @exact.Value,
  name : String,
  path : Array[String],
) -> @exact.Value raise DecodeError {
  match value.get(name) {
    Some(v) => v
    None =>
      raise DecodeError(
        @exact.Diagnostic::new(
          @exact.MissingField,
          "Missing required field: " + name,
          path~,
        ),
      )
  }
}

///|
fn text(
  value : @exact.Value,
  path : Array[String],
  nonempty~ : Bool = false,
) -> String raise DecodeError {
  match value.text() {
    Some(v) if !nonempty || !v.is_empty() => v
    _ =>
      raise DecodeError(
        @exact.Diagnostic::new(
          @exact.WrongType,
          "Expected a string" +
          (if nonempty { " with at least one character" } else { "" }),
          path~,
        ),
      )
  }
}

///|
fn array(
  value : @exact.Value,
  path : Array[String],
) -> Array[@exact.Value] raise DecodeError {
  match value.kind() {
    @exact.Array(values) => values
    _ =>
      raise DecodeError(
        @exact.Diagnostic::new(@exact.WrongType, "Expected an array", path~),
      )
  }
}

///|
fn child(path : Array[String], part : String) -> Array[String] {
  let out = path.copy()
  out.push(part)
  out
}

///|
fn reference(
  value : @exact.Value,
  path : Array[String],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> @reference.Reference? raise DecodeError {
  object(value, path) |> ignore
  match value.get("$ref") {
    None => None
    Some(raw) =>
      match
        @reference.Reference::parse(text(raw, child(path, "$ref")), limits~) {
        Ok(ref_) => Some(ref_)
        Err(d) =>
          raise DecodeError(
            @exact.Diagnostic::new(
              d.code(),
              d.message(),
              path=child(path, "$ref"),
            ),
          )
      }
  }
}

///|
fn descriptor(
  value : @exact.Value,
  path : Array[String],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> InlineOrReference[ContentDescriptor] raise DecodeError {
  if reference(value, path, limits~) is Some(ref_) {
    return Reference(ref_)
  }
  let name = text(
    field(value, "name", path),
    child(path, "name"),
    nonempty=true,
  )
  check_strings(value, path, ["summary", "description"])
  check_bools(value, path, ["deprecated"])
  let schema = match
    @schema.Schema::from_json(field(value, "schema", path), limits~) {
    Ok(schema) => schema
    Err(d) => {
      let schema_path = child(path, "schema")
      for part in d.path() {
        schema_path.push(part)
      }
      raise DecodeError(
        @exact.Diagnostic::new(d.code(), d.message(), path=schema_path),
      )
    }
  }
  let required = match value.get("required") {
    None => None
    Some(v) =>
      match v.kind() {
        @exact.Boolean(b) => Some(b)
        _ =>
          raise DecodeError(
            @exact.Diagnostic::new(
              @exact.WrongType,
              "Expected a required boolean",
              path=child(path, "required"),
            ),
          )
      }
  }
  Inline({ name, schema, required, value, })
}

///|
fn method_(
  value : @exact.Value,
  path : Array[String],
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> InlineOrReference[Method] raise DecodeError {
  if reference(value, path, limits~) is Some(ref_) {
    return Reference(ref_)
  }
  let raw_name = text(
    field(value, "name", path),
    child(path, "name"),
    nonempty=true,
  )
  let name = MethodName::parse(raw_name).unwrap()
  let raw_params = array(field(value, "params", path), child(path, "params"))
  let params = raw_params.mapi((i, v) => {
    descriptor(v, child(child(path, "params"), i.to_string()), limits~)
  })
  let result = match value.get("result") {
    None => None
    Some(v) => Some(descriptor(v, child(path, "result"), limits~))
  }
  let param_structure = match value.get("paramStructure") {
    None => None
    Some(v) =>
      match v.text() {
        Some("by-name") => Some(ByName)
        Some("by-position") => Some(ByPosition)
        Some("either") => Some(Either)
        _ =>
          raise DecodeError(
            @exact.Diagnostic::new(
              @exact.WrongType,
              "Expected by-name, by-position or either",
              path=child(path, "paramStructure"),
            ),
          )
      }
  }
  check_strings(value, path, ["summary", "description"])
  check_bools(value, path, ["deprecated"])
  if value.get("externalDocs") is Some(v) {
    documentation_(v, child(path, "externalDocs"), limits) |> ignore
  }
  optional_array_(value, "servers", path, server_, limits~) |> ignore
  optional_array_(value, "tags", path, tag_ref, limits~) |> ignore
  optional_array_(value, "errors", path, error_ref, limits~) |> ignore
  optional_array_(value, "links", path, link_ref, limits~) |> ignore
  optional_array_(value, "examples", path, pairing_ref, limits~) |> ignore
  Inline({ name, params, result, param_structure, value, })
}

///|
pub fn Document::from_json(
  value : @exact.Value,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[Document, Array[@exact.Diagnostic]] {
  match @exact.write(value, limits~) {
    Err(d) => return Err([d])
    Ok(_) => ()
  }
  try {
    object(value, []) |> ignore
    let version = match
      DocumentVersion::parse(text(field(value, "openrpc", []), ["openrpc"])) {
      Ok(v) => v
      Err(d) => raise DecodeError(d)
    }
    let raw_info = field(value, "info", [])
    let info = info_(raw_info, ["info"], limits)
    let methods = array(field(value, "methods", []), ["methods"]).mapi((i, v) => {
      method_(v, ["methods", i.to_string()], limits~)
    })
    let schema_uri = match value.get("$schema") {
      Some(v) => Some(uri_(v, ["$schema"], limits))
      None => None
    }
    let servers = optional_array_(value, "servers", [], server_, limits~)
    let components = match value.get("components") {
      Some(v) => Some(components_(v, ["components"], limits))
      None => None
    }
    let external_docs = match value.get("externalDocs") {
      Some(v) => Some(documentation_(v, ["externalDocs"], limits))
      None => None
    }
    Ok({
      version,
      info,
      methods,
      value,
      schema_uri,
      servers,
      components,
      external_docs,
    })
  } catch {
    DecodeError(d) => Err([d])
  }
}

///|
pub fn lower(cst : @exact.CstDocument) -> ReadResult {
  match cst.lower() {
    Err(diagnostics) => { cst: Some(cst), document: None, diagnostics, }
    Ok(value) =>
      match Document::from_json(value, limits=cst.limits()) {
        Ok(document) =>
          { cst: Some(cst), document: Some(document), diagnostics: [], }
        Err(diagnostics) =>
          {
            cst: Some(cst),
            document: None,
            diagnostics: diagnostics.map(d => {
              @exact.Diagnostic::new(
                d.code(),
                d.message(),
                path=d.path(),
                span=cst.span_at(d.path()),
                related=d.related(),
              )
            }),
          }
      }
  }
}

///|
pub fn read(
  source : String,
  source_id~ : String? = None,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> ReadResult {
  match @exact.parse(source, source_id~, limits~) {
    Ok(cst) => lower(cst)
    Err(d) => { cst: None, document: None, diagnostics: [d], }
  }
}

///|
/// Replace one existing value in a parsed document and read the result again.
/// Diagnostics use the new source map; node handles from `cst` become stale.
pub fn replace_value(
  cst : @exact.CstDocument,
  node : @exact.NodeId,
  value : @exact.Value,
  limits? : @exact.Limits,
) -> Result[ReadResult, @exact.Diagnostic] {
  match cst.replace_value(node, value, limits?) {
    Ok(edited) => Ok(lower(edited))
    Err(d) => Err(d)
  }
}
