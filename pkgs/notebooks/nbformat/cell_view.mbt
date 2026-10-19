///|
/// Classify this cell without discarding its format-specific payload.
pub fn Cell::kind(self : Cell) -> @notebooks.CellKind {
  match self.content {
    Code(_) => @notebooks.Code
    Markdown(_) => @notebooks.Markdown
    Raw(_) => @notebooks.Raw
    Unknown(cell_type~, ..) => @notebooks.Unknown(cell_type)
  }
}

///|
pub impl @notebooks.CellView for Cell with fn kind(self) {
  self.kind()
}

///|
pub impl @notebooks.CellView for Cell with fn source(self) {
  self.source()
}

///|
pub impl @notebooks.CellView for Cell with fn metadata(self) {
  Some(self.metadata())
}

///|
/// Every Jupyter cell supports MIME lookup. Cells without rich output or
/// attachments still return Some, and their lookup predicate returns false.
pub impl @notebooks.CellView for Cell with fn mime_capability(self) {
  Some(self as &@notebooks.MimeTyped)
}

///|
pub extend Cell with @notebooks.CellView::{mime_capability}
