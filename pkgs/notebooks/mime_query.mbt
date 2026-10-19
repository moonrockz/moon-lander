///|
/// An optional capability for querying the MIME representations of a cell.
/// Implementing this trait means lookup is supported, even when a particular
/// cell has no representations. Formats without MIME data should omit it.
pub(open) trait MimeTyped {
  /// Whether a representation with this exact MIME key is present.
  /// Match keys case-sensitively without wildcards or parameter normalization.
  /// Empty payloads and JSON null count as present.
  fn has_mime_type(Self, String) -> Bool
}

///|
/// Select MIME-capable cells in input order, retaining each matching input
/// position once. The immutable result preserves the concrete cell type.
/// The trait bound rejects unsupported cell types at compile time.
pub fn[C : MimeTyped] cells_by_mime_type(
  cells : ReadOnlyArray[C],
  mime_type : String,
) -> ReadOnlyArray[C] {
  ReadOnlyArray::from_iter(
    cells.iter().filter(cell => cell.has_mime_type(mime_type)),
  )
}
