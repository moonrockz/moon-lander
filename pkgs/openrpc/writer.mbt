///|
/// Canonical JSON for a document. It is not source reproduction (see
/// `CstDocument::reproduce`) and not RFC 8785 canonicalization.
pub fn write(
  document : Document,
  format~ : @exact.Format = Compact,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[String, @exact.Diagnostic] {
  @exact.write(document.to_json(), format~, limits~)
}
