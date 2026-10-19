///|
/// Whether a rich output or attachment contains this exact MIME key.
/// Source text and metadata are not searched. Empty payloads and JSON null
/// count as present; matching follows MimeBundle::get.
pub fn Cell::has_mime_type(self : Cell, mime_type : String) -> Bool {
  match self.content {
    Code(outputs~, ..) => {
      for output in outputs {
        match output.content {
          DisplayData(data~, ..) | ExecuteResult(data~, ..) =>
            if data.object.fields.contains(mime_type) {
              return true
            }
          Stream(_) | Error(_) | Unknown(_) => ()
        }
      }
      false
    }
    Markdown(attachments=Some(attachments), ..)
    | Raw(attachments=Some(attachments), ..) => {
      for (_, data) in attachments.entries {
        if data.object.fields.contains(mime_type) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
pub impl @notebooks.MimeTyped for Cell with fn has_mime_type(self, mime_type) {
  self.has_mime_type(mime_type)
}

///|
/// Select cells containing an exact MIME key in a rich output or attachment.
/// Return each matching cell once, in document order, in an immutable array.
/// Empty or JSON null payloads count as present. Matching is case-sensitive,
/// without wildcard or parameter normalization, just like MimeBundle::get.
/// Source text, metadata, streams, errors and unknown payloads are not searched.
/// Return an empty array when there are no matches.
pub fn Notebook::cells_by_mime_type(
  self : Notebook,
  mime_type : String,
) -> ReadOnlyArray[Cell] {
  @notebooks.cells_by_mime_type(self.cells, mime_type)
}
