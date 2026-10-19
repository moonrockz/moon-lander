///|
fn optional_type(
  object : JsonObject,
  key : String,
  kind : String,
  path : String,
) -> Unit raise FormatError {
  if object.fields.get(key) is Some(value) {
    let valid = match (kind, value) {
      ("string", String(_))
      | ("boolean", True | False)
      | ("object", Object(_))
      | ("array", Array(_)) => true
      _ => false
    }
    if !valid {
      invalid(path + "." + key, kind)
    }
  }
}

///|
fn validate_notebook_metadata(
  metadata : Metadata,
  path : String,
) -> Unit raise FormatError {
  let metadata = object_at(metadata_json_at(metadata, path), path)
  for key in ["kernelspec", "language_info", "kernel_info"] {
    if metadata.fields.get(key) is Some(value) {
      let nested_path = path + "." + key
      let object = object_at(value, nested_path)
      ignore(
        string_at(field(object, "name", nested_path), nested_path + ".name"),
      )
      if key == "kernelspec" {
        ignore(
          string_at(
            field(object, "display_name", nested_path),
            nested_path + ".display_name",
          ),
        )
      }
      if key == "language_info" {
        for name in ["file_extension", "mimetype", "pygments_lexer", "version"] {
          optional_type(object, name, "string", nested_path)
        }
        if object.fields.get("codemirror_mode") is Some(value) {
          guard value is (String(_) | Object(_)) else {
            invalid(nested_path + ".codemirror_mode", "string or object")
          }
        }
      }
    }
  }
  optional_type(metadata, "title", "string", path)
  if metadata.fields.get("orig_nbformat") is Some(value) {
    if integer_at(value, path + ".orig_nbformat") < 1 {
      invalid(path + ".orig_nbformat", "positive integer")
    }
  }
  if metadata.fields.get("authors") is Some(value) {
    for i, author in array_at(value, path + ".authors") {
      let author_path = "\{path}.authors[\{i}]"
      let object = object_at(author, author_path)
      ignore(
        string_at(field(object, "name", author_path), author_path + ".name"),
      )
    }
  }
}

///|
fn validate_cell_metadata(
  metadata : Metadata,
  kind : String,
  path : String,
) -> Unit raise FormatError {
  let metadata = object_at(metadata_json_at(metadata, path), path)
  for key in ["deletable", "editable"] {
    optional_type(metadata, key, "boolean", path)
  }
  if metadata.fields.get("name") is Some(value) {
    if string_at(value, path + ".name").is_empty() {
      invalid(path + ".name", "nonempty cell name")
    }
  }
  if metadata.fields.get("tags") is Some(value) {
    let seen = Map([])
    for i, tag in strings_at(value, path + ".tags") {
      if tag.is_empty() || tag.contains(",") || seen.contains(tag) {
        invalid("\{path}.tags[\{i}]", "unique nonempty tag without commas")
      }
      seen[tag] = true
    }
  }
  if metadata.fields.get("jupyter") is Some(value) {
    let object = object_at(value, path + ".jupyter")
    optional_type(object, "source_hidden", "boolean", path + ".jupyter")
    optional_type(object, "outputs_hidden", "boolean", path + ".jupyter")
  }
  if kind == "raw" {
    optional_type(metadata, "format", "string", path)
  }
  if kind == "code" {
    optional_type(metadata, "collapsed", "boolean", path)
    if metadata.fields.get("scrolled") is Some(value) {
      guard value is (True | False | String("auto")) else {
        invalid(path + ".scrolled", "boolean or 'auto'")
      }
    }
    if metadata.fields.get("execution") is Some(value) {
      let object = object_at(value, path + ".execution")
      for key, item in object.fields {
        ignore(string_at(item, path + ".execution." + key))
      }
    }
  }
}

///|
fn validate_cells(
  cells : ReadOnlyArray[Cell],
  minor : Int32,
) -> Unit raise FormatError {
  let ids = Map([])
  let names = Map([])
  for i, cell in cells {
    match cell.id {
      Some(id) => {
        if ids.contains(id.value) {
          raise DuplicateCellId(id.value)
        }
        ids[id.value] = true
      }
      None if minor >= 5 =>
        invalid(
          "$.cells[\{i}].id",
          "required cell ID in nbformat 4.5 and later",
        )
      None => ()
    }
    if cell.metadata.get("name") is Some(value) && value.kind() is String(name) {
      if names.contains(name) {
        raise DuplicateCellName(name)
      }
      names[name] = true
    }
  }
}
