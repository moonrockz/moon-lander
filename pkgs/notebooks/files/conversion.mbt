///|
/// A pure text-tree representation. Reading is an explicit tree projection;
/// writing creates a fresh document containing that tree.
pub(open) trait TreeFormat {
  /// Read the explicitly declared files and directories.
  fn read(Self, String) -> FileTree raise
  /// Write a fresh representation of the supplied tree.
  fn write(Self, FileTree) -> String raise
}

///|
/// Convert tree documents through the shared model. This does not preserve
/// unrelated notebook notes, metadata, outputs or attachments.
pub fn convert_tree(
  text : String,
  source~ : &TreeFormat,
  target~ : &TreeFormat,
) -> String raise {
  target.write(source.read(text))
}
