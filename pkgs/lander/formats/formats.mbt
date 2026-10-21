///|
/// The linked file formats, in candidate order.
pub fn formats() -> Array[@config.Format] {
  [@toml.format(), @yaml.format(), @json5.format(), @ion.format()]
}
