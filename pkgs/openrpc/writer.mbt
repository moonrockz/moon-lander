///|
pub fn write(
  document : Document,
  limits~ : @exact.Limits = @exact.Limits::new(),
) -> Result[String, @exact.Diagnostic] {
  @exact.write(document.to_json(), limits~)
}
