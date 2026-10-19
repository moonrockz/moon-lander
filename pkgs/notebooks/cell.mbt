///|
/// An immutable, format-independent cell view suitable for mixed collections.
/// All methods are object-safe, so cells from different formats can be stored
/// together as &CellView. Tree navigation remains on each format's Node type.
pub(open) trait CellView {
  /// The cell's common source role, retaining unknown format-specific names.
  fn kind(Self) -> CellKind
  /// Available source text, or None for an uninterpreted cell payload.
  fn source(Self) -> String?
  /// This cell's own immutable metadata, when the format provides it.
  fn metadata(Self) -> Metadata? = _
  /// Some means MIME lookup is supported, even if no representations exist.
  /// None means unsupported. The default is None; supporting formats must
  /// explicitly return a MimeTyped implementation for this cell.
  fn mime_capability(Self) -> Option[&MimeTyped] = _
}

///|
impl CellView with fn metadata(_self) {
  None
}

///|
impl CellView with fn mime_capability(_self) {
  None
}
