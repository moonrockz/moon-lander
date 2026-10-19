///|
/// Read notebook JSON into an immutable v4 document. Normalize multiline
/// strings and preserve unknown fields, cell types and output types.
/// Raise InvalidJson for malformed JSON, UnsupportedVersion for another
/// major version, or a typed FormatError for invalid structure or identities.
pub fn parse(source : String) -> Notebook raise FormatError {
  let value = @json.parse(source) catch {
    error => raise InvalidJson(error.to_string())
  }
  Notebook::from_json(value)
}

///|
/// Validate an existing JSON notebook and copy all mutable value graphs.
/// Accept v4 minor versions, requiring cell IDs from 4.5 onward. Raise
/// FormatError on invalid fields, unsupported major versions or duplicate
/// IDs/names. Later mutation of value cannot change the notebook.
pub fn Notebook::from_json(value : Json) -> Notebook raise FormatError {
  let object = object_at(value, "$")
  let major = integer_at(field(object, "nbformat", "$"), "$.nbformat")
  let minor = integer_at(
    field(object, "nbformat_minor", "$"),
    "$.nbformat_minor",
  )
  if major != 4 {
    raise UnsupportedVersion(major~, minor~)
  }
  let metadata = metadata_at(field(object, "metadata", "$"), "$.metadata")
  validate_notebook_metadata(metadata, "$.metadata")
  let raw_cells = array_at(field(object, "cells", "$"), "$.cells")
  let cells = ReadOnlyArray::from_array(
    raw_cells.mapi((i, cell) => cell_at(cell, "$.cells[\{i}]", minor))[:],
  )
  validate_cells(cells, minor)
  {
    minor,
    metadata,
    cells,
    extensions: remaining(object, [
      "nbformat", "nbformat_minor", "metadata", "cells",
    ]),
  }
}

///|
fn remaining(object : JsonObject, keys : Array[String]) -> JsonObject {
  let fields = Map([])
  for key, value in object.fields {
    if !keys.contains(key) {
      fields[key] = value
    }
  }
  { fields, }
}

///|
fn optional_count(
  object : JsonObject,
  path : String,
) -> ExecutionCount? raise FormatError {
  match field(object, "execution_count", path) {
    Null => None
    value => Some(count_at(value, path + ".execution_count"))
  }
}

///|
fn cell_at(
  value : Json,
  path : String,
  minor : Int32,
) -> Cell raise FormatError {
  let object = object_at(value, path)
  let kind = string_at(field(object, "cell_type", path), path + ".cell_type")
  let id = match object.fields.get("id") {
    Some(value) => Some(cell_id_at(value, path + ".id"))
    None if minor >= 5 =>
      invalid(path + ".id", "required cell ID in nbformat 4.5 and later")
    None => None
  }
  let metadata = metadata_at(
    field(object, "metadata", path),
    path + ".metadata",
  )
  validate_cell_metadata(metadata, kind, path + ".metadata")
  let keys = ["cell_type", "id", "metadata"]
  let content = match kind {
    "markdown" | "raw" => {
      keys.push("source")
      keys.push("attachments")
      let source = multiline(field(object, "source", path), path + ".source")
      let attachments = object.fields
        .get("attachments")
        .map(value => attachments_at(value, path + ".attachments"))
      if kind == "markdown" {
        Markdown(source~, attachments~)
      } else {
        Raw(source~, attachments~)
      }
    }
    "code" => {
      keys.push("source")
      keys.push("execution_count")
      keys.push("outputs")
      let source = multiline(field(object, "source", path), path + ".source")
      let execution_count = optional_count(object, path)
      let raw_outputs = array_at(
        field(object, "outputs", path),
        path + ".outputs",
      )
      let outputs = ReadOnlyArray::from_array(
        raw_outputs.mapi((i, output) => {
          output_at(output, "\{path}.outputs[\{i}]")
        })[:],
      )
      Code(source~, execution_count~, outputs~)
    }
    _ => Unknown(cell_type=kind, fields=remaining(object, keys))
  }
  let extensions = match content {
    Unknown(_) => JsonObject::{ fields: {}, }
    _ => remaining(object, keys)
  }
  { id, metadata, content, extensions, }
}

///|
fn output_at(value : Json, path : String) -> Output raise FormatError {
  let object = object_at(value, path)
  let kind = string_at(
    field(object, "output_type", path),
    path + ".output_type",
  )
  let keys = ["output_type"]
  let content = match kind {
    "stream" => {
      keys.push("name")
      keys.push("text")
      Stream(
        name=string_at(field(object, "name", path), path + ".name"),
        text=multiline(field(object, "text", path), path + ".text"),
      )
    }
    "display_data" | "execute_result" => {
      keys.push("data")
      keys.push("metadata")
      let data = mime_at(field(object, "data", path), path + ".data")
      let metadata = metadata_at(
        field(object, "metadata", path),
        path + ".metadata",
      )
      optional_type(
        object_at(metadata_json_at(metadata, path + ".metadata"), path + ".metadata"),
        "isolated",
        "boolean",
        path + ".metadata",
      )
      if kind == "display_data" {
        DisplayData(data~, metadata~)
      } else {
        keys.push("execution_count")
        ExecuteResult(
          data~,
          metadata~,
          execution_count=optional_count(object, path),
        )
      }
    }
    "error" => {
      keys.push("ename")
      keys.push("evalue")
      keys.push("traceback")
      Error(
        ename=string_at(field(object, "ename", path), path + ".ename"),
        evalue=string_at(field(object, "evalue", path), path + ".evalue"),
        traceback=strings_at(
          field(object, "traceback", path),
          path + ".traceback",
        ),
      )
    }
    _ => Unknown(output_type=kind, fields=remaining(object, keys))
  }
  let extensions = match content {
    Unknown(_) => JsonObject::{ fields: {}, }
    _ => remaining(object, keys)
  }
  { content, extensions, }
}

///|
/// Export an independent notebook JSON object, retaining version numbers,
/// metadata and extension payloads. Multiline values use normalized strings.
/// Mutating the exported object does not alter this notebook.
pub fn Notebook::to_json(self : Notebook) -> Json raise FormatError {
  let fields = self.extensions.fields.copy()
  fields["nbformat"] = 4
  fields["nbformat_minor"] = Json(self.minor)
  fields["metadata"] = metadata_json_at(self.metadata, "$.metadata")
  fields["cells"] = Json(self.cells.map(cell => cell.to_json()))
  copy_json(Json(fields))
}

///|
/// Serialize notebook JSON with normalized multiline strings. Preserve
/// metadata and extensions, but not original whitespace, key order or line
/// splitting. The result can be passed to parse.
pub fn Notebook::to_string(self : Notebook) -> String raise FormatError {
  self.to_json().stringify()
}

///|
/// Export an independent cell object, including its discriminator, optional
/// ID, metadata, typed content and preserved fields. Text is normalized.
pub fn Cell::to_json(self : Cell) -> Json raise FormatError {
  let fields = match self.content {
    Unknown(fields~, ..) => fields.fields.copy()
    _ => self.extensions.fields.copy()
  }
  fields["cell_type"] = Json(self.cell_type())
  fields["metadata"] = metadata_json_at(self.metadata, "$.metadata")
  if self.id is Some(id) {
    fields["id"] = Json(id.value)
  }
  match self.content {
    Markdown(source~, attachments~) | Raw(source~, attachments~) => {
      fields["source"] = Json(source)
      if attachments is Some(attachments) {
        fields["attachments"] = attachments.to_json()
      }
    }
    Code(source~, execution_count~, outputs~) => {
      fields["source"] = Json(source)
      fields["execution_count"] = execution_count
        .map(count => count.value)
        .unwrap_or(Json::null())
      fields["outputs"] = Json(outputs.map(output => output.to_json()))
    }
    Unknown(_) => ()
  }
  copy_json(Json(fields))
}

///|
/// Export an independent output object with its discriminator, typed
/// payload and preserved fields. Text is normalized; JSON MIME data is retained.
pub fn Output::to_json(self : Output) -> Json raise FormatError {
  let fields = match self.content {
    Unknown(fields~, ..) => fields.fields.copy()
    _ => self.extensions.fields.copy()
  }
  fields["output_type"] = Json(self.output_type())
  match self.content {
    Stream(name~, text~) => {
      fields["name"] = Json(name)
      fields["text"] = Json(text)
    }
    DisplayData(data~, metadata~) => {
      fields["data"] = data.to_json()
      fields["metadata"] = metadata_json_at(metadata, "$.metadata")
    }
    ExecuteResult(data~, metadata~, execution_count~) => {
      fields["data"] = data.to_json()
      fields["metadata"] = metadata_json_at(metadata, "$.metadata")
      fields["execution_count"] = execution_count
        .map(count => count.value)
        .unwrap_or(Json::null())
    }
    Error(ename~, evalue~, traceback~) => {
      fields["ename"] = Json(ename)
      fields["evalue"] = Json(evalue)
      fields["traceback"] = Json(traceback)
    }
    Unknown(_) => ()
  }
  copy_json(Json(fields))
}
