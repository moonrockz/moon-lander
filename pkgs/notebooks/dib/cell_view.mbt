///|
pub impl @notebooks.CellView for Cell with fn kind(self) {
  self.kind()
}

///|
pub impl @notebooks.CellView for Cell with fn source(self) {
  Some(self.source())
}

///|
/// DIB has no stored MIME bundles, so capability inspection uses the shared
/// default of None. It also has no cell-local metadata container.
pub extend Cell with @notebooks.CellView::{metadata, mime_capability}
