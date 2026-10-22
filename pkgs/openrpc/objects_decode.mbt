///|
fn check_strings(
  value : @exact.Value,
  path : Array[String],
  names : Array[String],
) -> Unit raise DecodeError {
  for name in names {
    if value.get(name) is Some(v) {
      text(v, child(path, name)) |> ignore
    }
  }
}

///|
fn check_bools(
  value : @exact.Value,
  path : Array[String],
  names : Array[String],
) -> Unit raise DecodeError {
  for name in names {
    if value.get(name) is Some(v) && !(v.kind() is @exact.Boolean(_)) {
      raise DecodeError(
        @exact.Diagnostic::new(
          @exact.WrongType,
          "Expected a boolean",
          path=child(path, name),
        ),
      )
    }
  }
}

///|
fn uri_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> @reference.UriReference raise DecodeError {
  match @reference.UriReference::parse(text(value, path), limits~) {
    Ok(uri) => uri
    Err(d) =>
      raise DecodeError(@exact.Diagnostic::new(d.code(), d.message(), path~))
  }
}

///|
fn check_uris(
  value : @exact.Value,
  path : Array[String],
  names : Array[String],
  limits : @exact.Limits,
) -> Unit raise DecodeError {
  for name in names {
    if value.get(name) is Some(v) {
      uri_(v, child(path, name), limits) |> ignore
    }
  }
}

///|
fn contact_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Contact raise DecodeError {
  object(value, path) |> ignore
  check_strings(value, path, ["name", "email"])
  check_uris(value, path, ["url"], limits)
  { value, }
}

///|
fn license_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> License raise DecodeError {
  object(value, path) |> ignore
  check_strings(value, path, ["name"])
  check_uris(value, path, ["url"], limits)
  { value, }
}

///|
fn documentation_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> ExternalDocumentation raise DecodeError {
  object(value, path) |> ignore
  uri_(field(value, "url", path), child(path, "url"), limits) |> ignore
  check_strings(value, path, ["description"])
  { value, }
}

///|
fn variable_(
  value : @exact.Value,
  path : Array[String],
  _limits : @exact.Limits,
) -> ServerVariable raise DecodeError {
  object(value, path) |> ignore
  text(field(value, "default", path), child(path, "default")) |> ignore
  check_strings(value, path, ["description"])
  if value.get("enum") is Some(v) {
    for i, item in array(v, child(path, "enum")) {
      text(item, child(child(path, "enum"), i.to_string())) |> ignore
    }
  }
  { value, }
}

///|
fn server_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Server raise DecodeError {
  object(value, path) |> ignore
  text(field(value, "url", path), child(path, "url")) |> ignore
  check_strings(value, path, ["name", "summary", "description"])
  if value.get("variables") is Some(v) {
    for (name, variable) in object(v, child(path, "variables")) {
      variable_(variable, child(child(path, "variables"), name), limits)
      |> ignore
    }
  }
  { value, }
}

///|
fn tag_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Tag raise DecodeError {
  object(value, path) |> ignore
  text(field(value, "name", path), child(path, "name"), nonempty=true) |> ignore
  check_strings(value, path, ["summary", "description"])
  if value.get("externalDocs") is Some(v) {
    documentation_(v, child(path, "externalDocs"), limits) |> ignore
  }
  { value, }
}

///|
fn error_object_(
  value : @exact.Value,
  path : Array[String],
  _limits : @exact.Limits,
) -> ErrorObject raise DecodeError {
  object(value, path) |> ignore
  match field(value, "code", path).kind() {
    @exact.Numeric(n) =>
      match ErrorCode::from_number(n) {
        Ok(_) => ()
        Err(d) =>
          raise DecodeError(
            @exact.Diagnostic::new(
              d.code(),
              d.message(),
              path=child(path, "code"),
            ),
          )
      }
    _ =>
      raise DecodeError(
        @exact.Diagnostic::new(
          @exact.WrongType,
          "Expected an integer error code",
          path=child(path, "code"),
        ),
      )
  }
  text(field(value, "message", path), child(path, "message")) |> ignore
  { value, }
}

///|
fn example_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Example raise DecodeError {
  object(value, path) |> ignore
  check_strings(value, path, ["name", "summary", "description"])
  if value.get("value") is Some(_) && value.get("externalValue") is Some(_) {
    raise DecodeError(
      @exact.Diagnostic::new(
        @exact.WrongType,
        "value and externalValue are mutually exclusive",
        path=child(path, "externalValue"),
      ),
    )
  }
  check_uris(value, path, ["externalValue"], limits)
  { value, }
}

///|
fn example_ref(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> InlineOrReference[Example] raise DecodeError {
  match reference(value, path, limits~) {
    Some(ref_) => Reference(ref_)
    None => Inline(example_(value, path, limits))
  }
}

///|
fn pairing_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> ExamplePairing raise DecodeError {
  object(value, path) |> ignore
  text(field(value, "name", path), child(path, "name"), nonempty=true) |> ignore
  check_strings(value, path, ["summary", "description"])
  for i, param in array(field(value, "params", path), child(path, "params")) {
    example_ref(param, child(child(path, "params"), i.to_string()), limits)
    |> ignore
  }
  if value.get("result") is Some(v) {
    example_ref(v, child(path, "result"), limits) |> ignore
  }
  { value, }
}

///|
fn link_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Link raise DecodeError {
  object(value, path) |> ignore
  if value.get("name") is Some(v) {
    text(v, child(path, "name"), nonempty=true) |> ignore
  }
  check_strings(value, path, ["summary", "description"])
  if value.get("method") is Some(v) {
    match MethodName::parse(text(v, child(path, "method"))) {
      Ok(_) => ()
      Err(d) =>
        raise DecodeError(
          @exact.Diagnostic::new(
            d.code(),
            d.message(),
            path=child(path, "method"),
          ),
        )
    }
  }
  if value.get("params") is Some(v) {
    object(v, child(path, "params")) |> ignore
  }
  if value.get("server") is Some(v) {
    server_(v, child(path, "server"), limits) |> ignore
  }
  { value, }
}

///|
fn info_(
  value : @exact.Value,
  path : Array[String],
  limits : @exact.Limits,
) -> Info raise DecodeError {
  object(value, path) |> ignore
  let title = text(field(value, "title", path), child(path, "title"))
  let version = text(field(value, "version", path), child(path, "version"))
  check_strings(value, path, ["description"])
  check_uris(value, path, ["termsOfService"], limits)
  if value.get("contact") is Some(v) {
    contact_(v, child(path, "contact"), limits) |> ignore
  }
  if value.get("license") is Some(v) {
    license_(v, child(path, "license"), limits) |> ignore
  }
  { title, version, value, }
}
